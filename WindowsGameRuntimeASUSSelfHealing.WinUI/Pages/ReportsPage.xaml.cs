using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class ReportsPage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private readonly BrokerService _broker = App.Services.Broker;
    private readonly ObservableCollection<ReportItem> _reports = new();
    private readonly ObservableCollection<TransactionItem> _transactions = new();
    private bool _loaded;

    public ReportsPage()
    {
        InitializeComponent();
        ReportsList.ItemsSource = _reports;
        TxList.ItemsSource = _transactions;
        ReportsList.SelectionChanged += (_, _) => OpenSelectedButton.IsEnabled = ReportsList.SelectedItem is ReportItem;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            await RefreshAsync();
        };
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async Task RefreshAsync()
    {
        RefreshButton.IsEnabled = false;
        try
        {
            await RefreshTransactionsAsync();
            var reports = await App.Services.Reports.ListReportsAsync();
            _reports.Clear();
            foreach (var item in reports) _reports.Add(item);
            var workflow = App.Services.Workflow.Current;
            WorkflowText.Text = workflow.State is "Idle" or "" ? "当前没有正在进行的修复。" : StatusPalette.Display(workflow.State);
            Info.Title = "报告已同步";
            Info.Message = $"报告 {_reports.Count} 份，修复记录 {_transactions.Count} 条。";
            Info.Severity = InfoBarSeverity.Success;
        }
        catch (Exception ex)
        {
            Info.Title = "报告中心刷新失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { RefreshButton.IsEnabled = true; }
    }

    private async Task RefreshTransactionsAsync()
    {
        try
        {
            using var r = await _backend.RunAsync("TRANSACTIONS", timeout: TimeSpan.FromMinutes(2));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            var rows = r.Payload.Array("Transactions").Select(PageHelpers.ToTransaction).ToArray();
            await App.Services.StateStore.UpsertTransactionsAsync(rows);
            _transactions.Clear();
            foreach (var row in rows) _transactions.Add(row);

            if (r.Payload.TryGetProperty("Open", out var open) && open.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                await App.Services.Workflow.RecordTransactionStateAsync(open.String("Type"), open.String("Group"), open.String("State"), open.String("LastDetail"));
                TransactionInfo.Title = "有未完成的修复";
                TransactionInfo.Message = CustomerCopy.Plain(open.String("LastDetail"));
                TransactionInfo.Severity = InfoBarSeverity.Warning;
            }
            else
            {
                TransactionInfo.Title = "没有未完成的修复";
                TransactionInfo.Message = "现在不用续跑。";
                TransactionInfo.Severity = InfoBarSeverity.Success;
            }
        }
        catch (Exception ex)
        {
            var cached = await App.Services.StateStore.ReadTransactionsAsync();
            _transactions.Clear();
            foreach (var row in cached) _transactions.Add(row);
            TransactionInfo.Title = cached.Count > 0 ? "正在显示上次记录" : "读取失败";
            TransactionInfo.Message = cached.Count > 0
                ? "刚才没读到最新记录，先显示上次结果。"
                : CustomerCopy.Plain(ex.Message);
            TransactionInfo.Severity = cached.Count > 0 ? InfoBarSeverity.Warning : InfoBarSeverity.Error;
        }
    }

    private async void SystemReport_Click(object sender, RoutedEventArgs e)
    {
        await GenerateReportAsync(SystemReportButton, "系统健康报告", () => App.Services.Reports.GenerateSystemHealthReportAsync());
    }

    private async void RepairReport_Click(object sender, RoutedEventArgs e)
    {
        await GenerateReportAsync(RepairReportButton, "修复报告", () => App.Services.Reports.GenerateRepairReportAsync());
    }

    private async void VerifyButton_Click(object sender, RoutedEventArgs e)
    {
        VerifyButton.IsEnabled = false;
        try
        {
            await App.Services.Workflow.RecordVerificationStartedAsync();
            using var r = await _backend.RunAsync("VERIFY", timeout: TimeSpan.FromMinutes(5));
            var detail = r.Success ? "检测完成，结果已保存到报告中心。" : CustomerCopy.Plain(r.Error);
            var backendState = "FAILED";
            if (r.Success)
            {
                backendState = "VERIFIED";
                if (r.Payload.TryGetProperty("Open", out var open) && open.ValueKind == System.Text.Json.JsonValueKind.Object)
                    backendState = open.String("State");
            }
            await App.Services.Workflow.RecordVerificationResultAsync(r.Success, backendState, detail);
            Info.Title = r.Success ? "检测完成" : "检测失败";
            Info.Message = detail;
            Info.Severity = r.Success ? InfoBarSeverity.Success : InfoBarSeverity.Error;
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            await App.Services.Workflow.RecordVerificationResultAsync(false, "FAILED", ex.Message);
            Info.Title = "检测失败";
            Info.Message = CustomerCopy.Plain(ex.Message);
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { VerifyButton.IsEnabled = true; }
    }

    private async Task GenerateReportAsync(Button button, string title, Func<Task<string>> generator)
    {
        button.IsEnabled = false;
        try
        {
            await generator();
            Info.Title = title + "已生成";
            Info.Message = "已保存到报告中心。";
            Info.Severity = InfoBarSeverity.Success;
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            Info.Title = title + "生成失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { button.IsEnabled = true; }
    }

    private async void DiagnosticZip_Click(object sender, RoutedEventArgs e)
    {
        DiagnosticZipButton.IsEnabled = false;
        try
        {
            using var r = await _backend.RunAsync("EXPORT_REPORT", timeout: TimeSpan.FromMinutes(8));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            Info.Title = "诊断包已生成";
            Info.Message = "已保存到报告中心。";
            Info.Severity = InfoBarSeverity.Success;
        }
        catch (Exception ex)
        {
            Info.Title = "诊断 ZIP 生成失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { DiagnosticZipButton.IsEnabled = true; }
    }

    private void OpenSelected_Click(object sender, RoutedEventArgs e)
    {
        if (ReportsList.SelectedItem is ReportItem item) App.Services.Reports.OpenReport(item.Path);
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e) => App.Services.Reports.OpenReportFolder();
    private void OpenSettings_Click(object sender, RoutedEventArgs e) => NavigationService?.Navigate(new SettingsPage());

    private void CopyInstallInfo_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var appPath = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory,
                "WindowsGameRuntimeASUSSelfHealing.WinUI.exe");
            var root = Directory.GetParent(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar))?.FullName;
            var launcher = root is null ? "未找到" : Path.Combine(root, "SelfHealingCenter.exe");
            var version = FileVersionInfo.GetVersionInfo(appPath).FileVersion ?? "未知";
            var details = $"奥创修复中心 {version}{Environment.NewLine}" +
                $"Windows: {Environment.OSVersion.Version}{Environment.NewLine}" +
                $"运行中的程序: {appPath}{Environment.NewLine}" +
                $"启动器: {launcher} (存在: {File.Exists(launcher)}){Environment.NewLine}" +
                $"State: {Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowsGameRuntimeASUSSelfHealing", "State")}";
            Clipboard.SetText(details);
            Info.Title = "安装信息已复制";
            Info.Message = $"当前运行路径：{appPath}";
            Info.Severity = InfoBarSeverity.Success;
        }
        catch (Exception ex)
        {
            Info.Title = "复制安装信息失败";
            Info.Message = CustomerCopy.Plain(ex.Message);
            Info.Severity = InfoBarSeverity.Error;
        }
    }

    private async void ContinueButton_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "重启后续跑", "Broker 会检查 BootTime 和事务 Journal，只有满足续跑条件才继续。", "通过 UAC 续跑")) return;
        ContinueButton.IsEnabled = false;
        try
        {
            var current = App.Services.Workflow.Current;
            await App.Services.Workflow.RecordBrokerStartAsync(current.Type, current.Group);
            var result = await _broker.ExecuteAsync("CONTINUE");
            await App.Services.Workflow.RecordBrokerResultAsync(current.Type, current.Group, result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "续跑已返回" : "续跑未完成", result.Detail);
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            var current = App.Services.Workflow.Current;
            await App.Services.Workflow.RecordBrokerResultAsync(current.Type, current.Group, false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "续跑失败", ex.Message);
        }
        finally { ContinueButton.IsEnabled = true; }
    }
}
