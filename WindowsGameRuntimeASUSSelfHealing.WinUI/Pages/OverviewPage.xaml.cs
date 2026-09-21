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
        SummaryInfo.Title = "系统体检中";
        SummaryInfo.Message = "正在后台读取组件完整性与安全门禁；崩溃健康度优先读取 SQLite 缓存，不主动重复扫描事件历史。";
        try
        {
            using var result = await App.Services.Performance.MeasureAsync(
                "Home.HealthCheck",
                () => _backend.RunAsync("DASHBOARD", force: force, timeout: TimeSpan.FromMinutes(2)));
            if (!result.Success) throw new InvalidOperationException(result.Error);

            var components = result.Payload.Array("Components").Select(PageHelpers.ToComponent).ToArray();
            await App.Services.StateStore.UpsertComponentStatesAsync(components);
            var crashes = await App.Services.StateStore.ReadCrashEventGroupsAsync(7, 120);
            var health = App.Services.HealthScore.Calculate(components, result.Payload.Bool("BrokerValid"), crashes);
            ApplyHealth(health);
            await App.Services.Workflow.RecordDiagnosedAsync(health.Summary);

            var issues = components
                .Where(x => x.Status is "FAIL" or "REPAIR" or "WARN" or "UPDATE" or "NEEDS_REPAIR")
                .Take(5)
                .Select(x => $"[{x.Status}] {x.Name}：{x.Detail}")
                .ToList();
            if (crashes.Any(x => x.Severity == "FAIL"))
                issues.Add($"[崩溃] 近 7 天缓存有 {crashes.Count(x => x.Severity == "FAIL")} 个严重崩溃组，可到“崩溃 / Dump”查看。 ");
            IssueText.Text = issues.Count == 0 ? "当前没有发现需要立即处理的项目。" : string.Join("\n", issues);

            var profile = App.Services.Resources.Profile;
            ResourceModeText.Text = $"资源模式：{profile.Name} · CPU {profile.LogicalProcessors} 逻辑核心 · 可用内存预算 {profile.MemoryText} · 后台重任务最多 {profile.MaxBackgroundOperations} 个并发。";

            SummaryInfo.Title = $"健康度 {health.Score}/100";
            SummaryInfo.Severity = health.Score >= 90 ? InfoBarSeverity.Success : health.Score >= 72 ? InfoBarSeverity.Warning : InfoBarSeverity.Error;
            SummaryInfo.Message = health.Summary + "。健康度为本软件本地诊断指数，不是 Windows 官方评分。";
        }
        catch (Exception ex)
        {
            SummaryInfo.Severity = InfoBarSeverity.Error;
            SummaryInfo.Title = "系统体检失败";
            SummaryInfo.Message = ex.Message;
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

        SetDomain(AsusCard, AsusStatusText, AsusDetailText, health.AsusState, health.AsusSummary);
        SetDomain(RuntimeCard, RuntimeStatusText, RuntimeDetailText, health.RuntimeState, health.RuntimeSummary);
        SetDomain(CrashCard, CrashStatusText, CrashDetailText, health.CrashState, health.CrashSummary);
        SetDomain(SystemCard, SystemStatusText, SystemDetailText, health.SystemState, health.SystemSummary);
    }

    private static void SetDomain(Border card, TextBlock statusText, TextBlock detailText, string state, string summary)
    {
        card.Background = StatusPalette.Brush(state);
        statusText.Text = state switch { "PASS" => "正常", "WARN" => "需关注", "FAIL" => "需处理", _ => state };
        detailText.Text = summary;
    }

    private async void ReportButton_Click(object sender, RoutedEventArgs e)
    {
        ReportButton.IsEnabled = false;
        try
        {
            var path = await App.Services.Performance.MeasureAsync("Reports.SystemHealth", () => App.Services.Reports.GenerateSystemHealthReportAsync());
            await PageHelpers.ShowAsync(this, "系统报告已生成", path);
        }
        catch (Exception ex) { await PageHelpers.ShowAsync(this, "生成报告失败", ex.Message); }
        finally { ReportButton.IsEnabled = true; }
    }
}
