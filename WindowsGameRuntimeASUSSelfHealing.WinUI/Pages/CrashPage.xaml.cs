using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class CrashPage : Page
{
    private readonly CrashTelemetryService _telemetry = App.Services.CrashTelemetry;
    private readonly BrokerService _broker = App.Services.Broker;
    private readonly ObservableCollection<CrashEventItem> _events = new();
    private readonly ObservableCollection<DumpAnalysisResult> _dumpHistory = new();
    private bool _loaded;
    private string _currentDumpReport = "";
    private string _currentGpuReport = "";
    private GpuDiagnosisSnapshot? _gpuDiagnosis;

    public CrashPage()
    {
        InitializeComponent();
        CrashList.ItemsSource = _events;
        DumpHistoryList.ItemsSource = _dumpHistory;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            await LoadDumpHistoryAsync();
            await Task.WhenAll(RefreshAsync(), RunGpuDiagnosisAsync());
        };
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
        => await Task.WhenAll(RefreshAsync(), RunGpuDiagnosisAsync());

    private async void GpuDiagnosisButton_Click(object sender, RoutedEventArgs e) => await RunGpuDiagnosisAsync();

    private async Task RefreshAsync()
    {
        RefreshButton.IsEnabled = false;
        CrashInfo.Title = "正在读取";
        CrashInfo.Message = "正在查看最近的游戏崩溃记录。";
        CrashInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            var snapshot = await App.Services.Performance.MeasureAsync("Crash.IncrementalRefresh", () => _telemetry.RefreshAsync());
            _events.Clear();
            foreach (var item in snapshot.Events) _events.Add(item);
            GpuText.Text = snapshot.GpuLines.Count == 0 ? "这次没有新的显卡状态。" : string.Join("\n\n", snapshot.GpuLines);
            WerText.Text = snapshot.WerLines.Count == 0 ? "还没有给指定游戏打开自动保存。" : string.Join("\n", snapshot.WerLines);

            CrashInfo.Title = snapshot.FromIncrementalCache ? "已显示上次结果" : "读取完成";
            CrashInfo.Message = snapshot.FromIncrementalCache
                ? snapshot.Warning
                : _events.Count == 0 ? "近 7 天没有游戏崩溃记录。" : $"近 7 天有 {_events.Count} 组崩溃记录。";
            CrashInfo.Severity = snapshot.FromIncrementalCache ? InfoBarSeverity.Warning : _events.Count == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
        }
        catch (Exception ex)
        {
            CrashInfo.Title = "读取失败";
            CrashInfo.Message = ex.Message;
            CrashInfo.Severity = InfoBarSeverity.Error;
        }
        finally { RefreshButton.IsEnabled = true; }
    }


    private async Task RunGpuDiagnosisAsync()
    {
        GpuDiagnosisButton.IsEnabled = false;
        GpuSafeRepairButton.IsEnabled = false;
        GpuDiagnosisTitle.Text = "正在检查显卡…";
        GpuDiagnosisSummary.Text = "正在查看显存、驱动超时和最近崩溃文件。";
        try
        {
            var diagnosis = await App.Services.Performance.MeasureAsync("Crash.GpuDiagnosis", () => App.Services.GpuDiagnostics.AnalyzeAsync());
            var reportPath = await App.Services.Reports.CreateGpuDiagnosisReportAsync(diagnosis);
            diagnosis = diagnosis with { ReportPath = reportPath };
            _gpuDiagnosis = diagnosis;
            _currentGpuReport = reportPath;
            ApplyGpuDiagnosis(diagnosis);
        }
        catch (Exception ex)
        {
            GpuDiagnosisTitle.Text = "显卡检查失败";
            GpuDiagnosisSummary.Text = ex.Message;
            GpuEvidenceText.Text = "";
            GpuRepairPlanText.Text = "";
            OpenGpuReportButton.IsEnabled = false;
        }
        finally { GpuDiagnosisButton.IsEnabled = true; }
    }

    private void ApplyGpuDiagnosis(GpuDiagnosisSnapshot result)
    {
        GpuDiagnosisTitle.Text = $"{result.PrimaryCauseTitle} · {result.Confidence}";
        GpuDiagnosisSummary.Text = result.Summary;
        RebarText.Text = $"{result.RebarStatus}\n{result.RebarEvidence}";
        GpuMemoryText.Text = result.MemorySummary;
        GpuEventText.Text = result.EventSummary;
        GpuDumpText.Text = result.DumpSummary;
        GpuEvidenceText.Text = result.EvidenceText;
        GpuRepairPlanText.Text = result.RepairPlanText;
        GpuSafeRepairButton.IsEnabled = result.SafeAutoRepairAvailable;
        GpuSafeRepairButton.Content = string.IsNullOrWhiteSpace(result.SafeAutoRepairLabel) ? "安全清理显卡缓存" : result.SafeAutoRepairLabel;
        OpenGpuReportButton.IsEnabled = !string.IsNullOrWhiteSpace(result.ReportPath);
    }

    private void OpenGpuReportButton_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_currentGpuReport)) App.Services.Reports.OpenReport(_currentGpuReport);
    }

    private async void GpuSafeRepairButton_Click(object sender, RoutedEventArgs e)
    {
        if (_gpuDiagnosis?.SafeAutoRepairAvailable != true) return;
        var confirmed = await PageHelpers.ConfirmAsync(
            this,
            "清理显卡缓存",
            "只会把显卡缓存挪到备份目录，并重新扫描设备。不会卸载驱动，也不会改主板设置。建议先退出游戏。",
            "通过 UAC 执行");
        if (!confirmed) return;

        GpuSafeRepairButton.IsEnabled = false;
        try
        {
            var result = await _broker.ExecuteAsync("GPU_SAFE_REPAIR");
            await PageHelpers.ShowAsync(this, result.Success ? "清理完成" : "清理未完成", CustomerCopy.Plain(result.Detail));
            await RunGpuDiagnosisAsync();
        }
        catch (Exception ex)
        {
            await PageHelpers.ShowAsync(this, "清理失败", CustomerCopy.Plain(ex.Message));
        }
        finally
        {
            GpuSafeRepairButton.IsEnabled = _gpuDiagnosis?.SafeAutoRepairAvailable == true;
        }
    }

    private async void AnalyzeDump_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var dlg = new OpenFileDialog { Filter = "Minidump (*.dmp)|*.dmp|All files (*.*)|*.*" };
            if (dlg.ShowDialog() != true) return;
            var dumpPath = dlg.FileName;

            AnalyzeButton.IsEnabled = false;
            CrashInfo.Title = "正在分析 Dump";
            CrashInfo.Message = "使用 Windows DbgHelp 直接读取 Minidump 异常流和模块表，不会把文件上传到网络。";
            CrashInfo.Severity = InfoBarSeverity.Informational;

            var analysis = await App.Services.Performance.MeasureAsync("Crash.DumpAnalyze", () => App.Services.DumpAnalysis.AnalyzeAsync(dumpPath));
            var reportPath = await App.Services.Reports.CreateDumpAnalysisReportAsync(analysis);
            analysis = analysis with { ReportPath = reportPath };
            await App.Services.StateStore.SaveDumpAnalysisAsync(analysis);
            _currentDumpReport = reportPath;
            ApplyDumpResult(analysis);
            await LoadDumpHistoryAsync();
            await RunGpuDiagnosisAsync();

            CrashInfo.Title = "Dump 分析完成";
            CrashInfo.Message = $"{analysis.ExceptionCode} · {analysis.FaultingModule} · 置信度 {analysis.Confidence}";
            CrashInfo.Severity = analysis.Confidence == "HIGH" ? InfoBarSeverity.Warning : InfoBarSeverity.Informational;
        }
        catch (Exception ex)
        {
            CrashInfo.Title = "Dump 分析失败";
            CrashInfo.Message = ex.Message;
            CrashInfo.Severity = InfoBarSeverity.Error;
        }
        finally { AnalyzeButton.IsEnabled = true; }
    }

    private void ApplyDumpResult(DumpAnalysisResult result)
    {
        DumpReasonText.Text = result.CoreReason;
        DumpFileText.Text = $"{result.FileName} · {result.FileSizeText} · 分析时间 {result.AnalyzedText}";
        DumpExceptionText.Text = $"异常：{result.ExceptionCode} {result.ExceptionName} · 地址 {result.ExceptionAddress}";
        DumpModuleText.Text = $"故障模块：{result.FaultingModule} · 分类 {result.Category} · 置信度 {result.Confidence}";
        DumpEvidenceText.Text = result.Evidence;
        OpenDumpReportButton.IsEnabled = !string.IsNullOrWhiteSpace(result.ReportPath);
    }

    private async Task LoadDumpHistoryAsync()
    {
        var rows = await App.Services.StateStore.ReadDumpAnalysesAsync(12);
        _dumpHistory.Clear();
        foreach (var row in rows) _dumpHistory.Add(row);
    }

    private void OpenDumpReport_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_currentDumpReport)) App.Services.Reports.OpenReport(_currentDumpReport);
    }

    private async void EnableDump_Click(object sender, RoutedEventArgs e) => await SetDumpAsync(true);
    private async void DisableDump_Click(object sender, RoutedEventArgs e) => await SetDumpAsync(false);

    private async Task SetDumpAsync(bool enable)
    {
        var exe = ExeNameBox.Text.Trim();
        if (!System.Text.RegularExpressions.Regex.IsMatch(exe, @"^[A-Za-z0-9_.-]+\.exe$"))
        {
            await PageHelpers.ShowAsync(this, "EXE 名称无效", "请输入类似 game.exe 的文件名。");
            return;
        }
        try
        {
            var result = await _broker.ExecuteAsync(enable ? "WER_ENABLE" : "WER_DISABLE", exeName: exe);
            await PageHelpers.ShowAsync(this, enable ? "WER Dump" : "关闭 WER Dump", result.Detail);
            await RefreshAsync();
        }
        catch (Exception ex) { await PageHelpers.ShowAsync(this, "WER 配置失败", ex.Message); }
    }
}
