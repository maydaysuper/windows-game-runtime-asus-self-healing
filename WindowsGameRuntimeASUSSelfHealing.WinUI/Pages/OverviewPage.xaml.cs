using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class OverviewPage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private bool _loaded;

    public OverviewPage()
    {
        InitializeComponent();
        Loaded += OverviewPage_Loaded;
    }

    private async void OverviewPage_Loaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await RefreshAsync(false);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync(true);

    private async Task RefreshAsync(bool force)
    {
        RefreshButton.IsEnabled = false;
        SummaryInfo.Severity = InfoBarSeverity.Informational;
        SummaryInfo.Title = "正在体检";
        SummaryInfo.Message = "正在联网对比官方运行库，并查看奥创和崩溃。";
        try
        {
            using var result = await App.Services.Performance.MeasureAsync(
                "Home.HealthCheck",
                () => _backend.RunAsync("DASHBOARD", force: force, timeout: TimeSpan.FromMinutes(4)));
            if (!result.Success) throw new InvalidOperationException(result.Error);

            var components = result.Payload.Array("Components").Select(PageHelpers.ToComponent).ToArray();
            await App.Services.StateStore.UpsertComponentStatesAsync(components);
            var crashes = await App.Services.StateStore.ReadCrashEventGroupsAsync(7, 120);
            var health = App.Services.HealthScore.Calculate(components, result.Payload.Bool("BrokerValid"), crashes);
            ApplyHealth(health);
            ApplyAsusCard(result.Payload.StringArray("ActiveErrorCodes"), health, result.Payload.Bool("ArmouryCrateNeedsRepair"));
            try { await App.Services.Workflow.RecordDiagnosedAsync(health.Summary); }
            catch (Exception wf) { App.Services.SessionLog.Bug("Overview.RecordDiagnosed", wf); }

            var issues = components
                .Where(x => x.Status is "FAIL" or "REPAIR" or "WARN" or "UPDATE" or "NEEDS_REPAIR")
                .Take(5)
                .Select(x => $"{x.DisplayName}：{x.ResultLine}")
                .ToList();
            if (crashes.Any(x => x.Severity == "FAIL"))
                issues.Add($"近 7 天有 {crashes.Count(x => x.Severity == "FAIL")} 次严重崩溃，可到「游戏崩溃」查看。");
            IssueText.Text = issues.Count == 0 ? "结论：现在没有需要处理的项目。" : string.Join("\n", issues);

            SummaryInfo.Title = health.Score >= 90 ? "整体正常" : health.Score >= 72 ? "有项目需关注" : "有项目需处理";
            SummaryInfo.Severity = health.Score >= 90 ? InfoBarSeverity.Success : health.Score >= 72 ? InfoBarSeverity.Warning : InfoBarSeverity.Error;
            SummaryInfo.Message = health.Summary;
        }
        catch (Exception ex)
        {
            SummaryInfo.Severity = InfoBarSeverity.Error;
            SummaryInfo.Title = "体检失败";
            SummaryInfo.Message = CustomerCopy.Plain(ex.Message);
            App.Services.SessionLog.Bug("Overview.Health", ex);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }

    private void ApplyHealth(HealthScoreSnapshot health)
    {
        HealthScoreText.Text = health.Score.ToString();
        HealthText.Text = health.Summary;
        HealthProgress.Value = health.Score;
        HealthCard.Background = StatusPalette.Brush(health.State);
        HealthRing.BorderBrush = StatusPalette.Foreground(health.State);

        SetDomain(RuntimeCard, RuntimeStatusText, RuntimeDetailText, health.RuntimeState, health.RuntimeSummary);
        SetDomain(CrashCard, CrashStatusText, CrashDetailText, health.CrashState, health.CrashSummary);
        SetDomain(SystemCard, SystemStatusText, SystemDetailText, health.SystemState, health.SystemSummary);
    }

    private void ApplyAsusCard(string[] codes, HealthScoreSnapshot health, bool crateNeedsRepair)
    {
        var update = codes.Where(c =>
            c.Contains("4151", StringComparison.OrdinalIgnoreCase)
            || c.Contains("4152", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var install = codes.Any(c => c.Contains("501", StringComparison.OrdinalIgnoreCase) || c.Contains("601", StringComparison.OrdinalIgnoreCase));
        if (update.Length > 0)
        {
            AsusCard.Background = StatusPalette.Brush("FAIL");
            AsusStatusText.Text = "有更新错误";
            AsusDetailText.Text = "奥创更新失败。请到「奥创中心」全自动修。";
            return;
        }
        if (crateNeedsRepair)
        {
            AsusCard.Background = StatusPalette.Brush("FAIL");
            AsusStatusText.Text = install ? "安装 501" : "打不开";
            AsusDetailText.Text = "请到「奥创中心」全自动修。笔记本和台式机都能用。";
            return;
        }

        var state = health.AsusState is "FAIL" or "WARN" ? health.AsusState : "PASS";
        AsusCard.Background = StatusPalette.Brush(state);
        AsusStatusText.Text = state == "PASS" ? "无更新错误" : "需到奥创中心";
        AsusDetailText.Text = health.AsusSummary;
    }

    private static void SetDomain(Border card, TextBlock statusText, TextBlock detailText, string state, string summary)
    {
        card.Background = StatusPalette.Brush(state);
        statusText.Text = StatusPalette.Display(state);
        detailText.Text = summary;
    }

    private async void ReportButton_Click(object sender, RoutedEventArgs e)
    {
        ReportButton.IsEnabled = false;
        try
        {
            await App.Services.Performance.MeasureAsync("Reports.SystemHealth", () => App.Services.Reports.GenerateSystemHealthReportAsync());
            await PageHelpers.ShowAsync(this, "报告已生成", "已保存到报告中心。");
        }
        catch (Exception ex) { await PageHelpers.ShowAsync(this, "生成报告失败", CustomerCopy.Plain(ex.Message)); }
        finally { ReportButton.IsEnabled = true; }
    }
}
