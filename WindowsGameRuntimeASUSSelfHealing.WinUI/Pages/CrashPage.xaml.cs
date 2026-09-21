using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.Storage.Pickers;
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
        NavigationCacheMode = NavigationCacheMode.Enabled;
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
        CrashInfo.Title = "增量读取中";
        CrashInfo.Message = "仅从上次游标附近继续读取 Event Log；历史事件从本地 SQLite 聚合。";
        CrashInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            var snapshot = await App.Services.Performance.MeasureAsync("Crash.IncrementalRefresh", () => _telemetry.RefreshAsync());
            _events.Clear();
            foreach (var item in snapshot.Events) _events.Add(item);
            GpuText.Text = snapshot.GpuLines.Count == 0 ? "本次未刷新 GPU/PnP 实时状态。" : string.Join("\n\n", snapshot.GpuLines);
            WerText.Text = snapshot.WerLines.Count == 0 ? "未配置目标进程 LocalDumps，或本次使用离线缓存。" : string.Join("\n", snapshot.WerLines);

            CrashInfo.Title = snapshot.FromIncrementalCache ? "已显示本地缓存" : "增量读取完成";
            CrashInfo.Message = snapshot.FromIncrementalCache
                ? snapshot.Warning
                : $"新增 {snapshot.NewEventCount} 条原始事件；当前 {_events.Count} 个崩溃组。没有重新扫描全部历史。";
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
        GpuDiagnosisTitle.Text = "正在采集 GPU 证据…";
        GpuDiagnosisSummary.Text = "正在读取 ReBAR/BAR、GPU memory counters、TDR/驱动事件、WHEA、Kernel-Power、LiveKernelReports 和最近 Dump。";
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
            GpuDiagnosisTitle.Text = "GPU 诊断失败";
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
        GpuSafeRepairButton.Content = string.IsNullOrWhiteSpace(result.SafeAutoRepairLabel) ? "安全 GPU 修复" : result.SafeAutoRepairLabel;
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
            "执行安全 GPU 修复",
            "只会把当前用户的 DirectX/显卡 Shader Cache 改名迁移到本机备份目录，并执行 PnP 设备重扫描。不会 DDU、不会卸载驱动、不会写 BIOS/ReBAR、不会修改 TDR 注册表。建议先退出正在运行的游戏。",
            "通过 UAC 执行");
        if (!confirmed) return;

        GpuSafeRepairButton.IsEnabled = false;
        try
        {
            var result = await _broker.ExecuteAsync("GPU_SAFE_REPAIR");
            await PageHelpers.ShowAsync(this, result.Success ? "安全 GPU 修复完成" : "安全 GPU 修复未完成", result.Detail);
            await RunGpuDiagnosisAsync();
        }
        catch (Exception ex)
        {
            await PageHelpers.ShowAsync(this, "安全 GPU 修复失败", ex.Message);
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
            var app = (App)Application.Current;
            if (app.MainWindow is null) throw new InvalidOperationException("主窗口尚未就绪。");
            var picker = new FileOpenPicker();
            picker.FileTypeFilter.Add(".dmp");
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(app.MainWindow);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
            var file = await picker.PickSingleFileAsync();
            if (file is null) return;

            AnalyzeButton.IsEnabled = false;
            CrashInfo.Title = "正在分析 Dump";
            CrashInfo.Message = "使用 Windows DbgHelp 直接读取 Minidump 异常流和模块表，不会把文件上传到网络。";
            CrashInfo.Severity = InfoBarSeverity.Informational;

            var analysis = await App.Services.Performance.MeasureAsync("Crash.DumpAnalyze", () => App.Services.DumpAnalysis.AnalyzeAsync(file.Path));
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
