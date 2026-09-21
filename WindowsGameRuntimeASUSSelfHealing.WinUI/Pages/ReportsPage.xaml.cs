using System.Collections.ObjectModel;
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
            WorkflowText.Text = $"当前流程：{workflow.State} · {workflow.Type} {workflow.Group} · {workflow.Detail}";
            Info.Title = "报告已同步";
            Info.Message = $"本机报告 {_reports.Count} 份 · 修复事务 {_transactions.Count} 条。";
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
                TransactionInfo.Title = "存在未闭合修复事务";
                TransactionInfo.Message = $"{open.String("TransactionId")} · {open.String("State")} · {open.String("LastDetail")}";
                TransactionInfo.Severity = InfoBarSeverity.Warning;
            }
            else
            {
                TransactionInfo.Title = "修复事务状态正常";
                TransactionInfo.Message = "没有未完成事务；完整 Transaction ID、Journal 状态与修复详情仍保留。";
                TransactionInfo.Severity = InfoBarSeverity.Success;
            }
        }
        catch (Exception ex)
        {
            var cached = await App.Services.StateStore.ReadTransactionsAsync();
            _transactions.Clear();
            foreach (var row in cached) _transactions.Add(row);
            TransactionInfo.Title = cached.Count > 0 ? "正在显示本地事务缓存" : "事务读取失败";
            TransactionInfo.Message = cached.Count > 0
                ? "实时 Transaction 读取失败，当前保留 SQLite 历史：" + ex.Message
                : ex.Message;
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
            var detail = r.Success ? r.Payload.String("Path") : r.Error;
            var backendState = "FAILED";
            if (r.Success)
            {
                backendState = "VERIFIED";
                if (r.Payload.TryGetProperty("Open", out var open) && open.ValueKind == System.Text.Json.JsonValueKind.Object)
                    backendState = open.String("State");
            }
            await App.Services.Workflow.RecordVerificationResultAsync(r.Success, backendState, detail);
            Info.Title = r.Success ? "最终验收已返回" : "最终验收失败";
            Info.Message = detail;
            Info.Severity = r.Success ? InfoBarSeverity.Success : InfoBarSeverity.Error;
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            await App.Services.Workflow.RecordVerificationResultAsync(false, "FAILED", ex.Message);
            Info.Title = "最终验收失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { VerifyButton.IsEnabled = true; }
    }

    private async Task GenerateReportAsync(Button button, string title, Func<Task<string>> generator)
    {
        button.IsEnabled = false;
        try
        {
            var path = await generator();
            Info.Title = title + "已生成";
            Info.Message = path;
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
            Info.Title = "完整诊断 ZIP 已生成";
            Info.Message = r.Payload.String("Path");
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
    private void OpenSettings_Click(object sender, RoutedEventArgs e) => Frame.Navigate(new SettingsPage());

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
