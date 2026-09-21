using System.Diagnostics;
using System.Text;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class ReportService
{
    private readonly IBackendClient _backend;
    private readonly IStateStore _stateStore;
    private readonly HealthScoreService _healthScore;

    public string ReportRoot { get; }

    public ReportService(IBackendClient backend, IStateStore stateStore, HealthScoreService healthScore)
    {
        _backend = backend;
        _stateStore = stateStore;
        _healthScore = healthScore;
        ReportRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowsGameRuntimeASUSSelfHealing", "Reports");
    }

    public async Task<string> GenerateSystemHealthReportAsync(CancellationToken cancellationToken = default)
    {
        using var result = await _backend.RunAsync("DASHBOARD", force: true, timeout: TimeSpan.FromMinutes(3), cancellationToken: cancellationToken).ConfigureAwait(false);
        if (!result.Success) throw new InvalidOperationException(result.Error);

        var components = result.Payload.Array("Components").Select(Pages.PageHelpers.ToComponent).ToArray();
        await _stateStore.UpsertComponentStatesAsync(components, cancellationToken).ConfigureAwait(false);
        var crashes = await _stateStore.ReadCrashEventGroupsAsync(7, 120, cancellationToken).ConfigureAwait(false);
        var health = _healthScore.Calculate(components, result.Payload.Bool("BrokerValid"), crashes);
        var status = await _stateStore.GetStatusAsync(cancellationToken).ConfigureAwait(false);

        var text = new StringBuilder();
        text.AppendLine("# 奥创修复中心 系统健康报告");
        text.AppendLine();
        text.AppendLine($"- 时间：{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}");
        text.AppendLine($"- 总分：**{health.Score}/100**（{health.Summary}）");
        text.AppendLine($"- 奥创：{health.AsusSummary}");
        text.AppendLine($"- 运行库：{health.RuntimeSummary}");
        text.AppendLine($"- 崩溃：{health.CrashSummary}");
        text.AppendLine($"- 系统保护：{health.SystemSummary}");
        text.AppendLine();
        text.AppendLine("## 检测结果");
        foreach (var row in components)
            text.AppendLine($"- {row.DisplayStatus}  {row.DisplayName}：{row.ResultLine}");
        text.AppendLine();
        text.AppendLine("## 记录");
        text.AppendLine($"- 崩溃记录：{status.CrashEventCount}");
        text.AppendLine($"- 修复记录：{status.TransactionCount}");
        text.AppendLine();
        text.AppendLine("> 分数是本软件的本地判断，不是 Windows 官方评分。");

        return await WriteReportAsync("SYSTEM", "SystemHealth", text.ToString(), cancellationToken).ConfigureAwait(false);
    }

    public async Task<string> GenerateRepairReportAsync(CancellationToken cancellationToken = default)
    {
        var transactions = await _stateStore.ReadTransactionsAsync(100, cancellationToken).ConfigureAwait(false);
        var workflow = await _stateStore.GetWorkflowAsync(cancellationToken).ConfigureAwait(false);
        var text = new StringBuilder();
        text.AppendLine("# Windows Game Runtime 修复报告");
        text.AppendLine();
        text.AppendLine($"- 生成时间：{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}");
        if (workflow is not null)
            text.AppendLine($"- 当前流程：{workflow.State} / {workflow.Type} {workflow.Group} / {workflow.Detail}");
        text.AppendLine();
        text.AppendLine("## 修复事务");
        if (transactions.Count == 0) text.AppendLine("暂无修复事务。\n");
        foreach (var tx in transactions)
        {
            text.AppendLine($"### {tx.Label} — {tx.State}");
            text.AppendLine($"- Transaction ID：{tx.TransactionId}");
            text.AppendLine($"- 类型：{tx.Type} / {tx.Group}");
            text.AppendLine($"- 时间：{tx.StartedAt} → {tx.UpdatedAt}");
            text.AppendLine($"- 结果：{tx.LastDetail}");
            text.AppendLine();
        }
        return await WriteReportAsync("REPAIR", "RepairHistory", text.ToString(), cancellationToken).ConfigureAwait(false);
    }

    public async Task<string> CreateDumpAnalysisReportAsync(DumpAnalysisResult result, CancellationToken cancellationToken = default)
    {
        var text = new StringBuilder();
        text.AppendLine("# 游戏 Dump 分析报告");
        text.AppendLine();
        text.AppendLine($"- Dump：{result.FileName}");
        text.AppendLine($"- 文件大小：{result.FileSizeText}");
        text.AppendLine($"- 分析时间：{result.AnalyzedText}");
        text.AppendLine($"- 异常码：{result.ExceptionCode} {result.ExceptionName}");
        text.AppendLine($"- 异常地址：{result.ExceptionAddress}");
        text.AppendLine($"- 故障模块：{result.FaultingModule}");
        text.AppendLine($"- 分类：{result.Category}");
        text.AppendLine($"- 置信度：{result.Confidence}");
        text.AppendLine();
        text.AppendLine("## 核心报错方向");
        text.AppendLine(result.CoreReason);
        text.AppendLine();
        text.AppendLine("## 证据");
        text.AppendLine(result.Evidence);
        text.AppendLine();
        text.AppendLine("> 当前内置分析器直接读取 Windows Minidump 异常流与模块表，不需要上传 Dump。未加载厂商符号时，结论表示核心报错点/最可能方向，不冒充完整符号化调用栈的最终根因。");
        return await WriteReportAsync("DUMP", Path.GetFileNameWithoutExtension(result.FileName), text.ToString(), cancellationToken).ConfigureAwait(false);
    }

    public async Task<string> CreateGpuDiagnosisReportAsync(GpuDiagnosisSnapshot result, CancellationToken cancellationToken = default)
    {
        var text = new StringBuilder();
        text.AppendLine("# GPU / ReBAR 黑屏与爆显存诊断报告");
        text.AppendLine();
        text.AppendLine($"- 分析时间：{result.AnalyzedText}");
        text.AppendLine($"- 首要方向：**{result.PrimaryCauseTitle}**（{result.PrimaryCauseCode}）");
        text.AppendLine($"- 置信度：{result.Confidence}");
        text.AppendLine($"- ReBAR：{result.RebarStatus}");
        text.AppendLine($"- GPU Memory：{result.MemorySummary}");
        text.AppendLine($"- Event Log：{result.EventSummary}");
        text.AppendLine($"- 最近 Dump：{result.DumpSummary}");
        text.AppendLine();
        text.AppendLine("## 核心判断");
        text.AppendLine(result.Summary);
        text.AppendLine();
        text.AppendLine("## 证据链");
        foreach (var row in result.Evidence) text.AppendLine("- " + row);
        text.AppendLine();
        text.AppendLine("## 处理建议");
        foreach (var row in result.RepairPlan) text.AppendLine("- " + row);
        text.AppendLine();
        text.AppendLine($"- 安全自动修复：{(result.SafeAutoRepairAvailable ? result.SafeAutoRepairLabel : "不可用 / 不适用")}");
        text.AppendLine();
        text.AppendLine("> 该结论基于本机显存计数器、ReBAR/BAR 证据、TDR/显示驱动事件、WHEA、Kernel-Power、LiveKernelReports 和最近 Dump 的组合证据。供电问题无法仅靠 Windows 软件直接测量 PSU 电压，因此供电分类只会以“嫌疑”形式出现。程序不会自动 DDU、不会写 BIOS/ReBAR、不会卸载显示驱动，也不会修改 TdrDelay/TdrDdiDelay。");
        return await WriteReportAsync("GPU", result.PrimaryCauseCode, text.ToString(), cancellationToken).ConfigureAwait(false);
    }

    public Task<IReadOnlyList<ReportItem>> ListReportsAsync(int max = 60, CancellationToken cancellationToken = default)
        => Task.Run<IReadOnlyList<ReportItem>>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            Directory.CreateDirectory(ReportRoot);
            return Directory.EnumerateFiles(ReportRoot, "*.md", SearchOption.TopDirectoryOnly)
                .Select(path => new FileInfo(path))
                .OrderByDescending(x => x.LastWriteTimeUtc)
                .Take(Math.Clamp(max, 1, 200))
                .Select(x => new ReportItem
                {
                    Type = TypeFromName(x.Name),
                    Title = x.Name,
                    CreatedText = x.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"),
                    Summary = $"{x.Length / 1024d:0.0} KB",
                    Path = x.FullName
                }).ToArray();
        }, cancellationToken);

    public void OpenReport(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("报告不存在。", path);
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    }

    public void OpenReportFolder()
    {
        Directory.CreateDirectory(ReportRoot);
        Process.Start(new ProcessStartInfo(ReportRoot) { UseShellExecute = true });
    }

    private async Task<string> WriteReportAsync(string type, string label, string content, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(ReportRoot);
        var safe = new string(label.Where(c => char.IsLetterOrDigit(c) || c is '-' or '_').Take(50).ToArray());
        if (string.IsNullOrWhiteSpace(safe)) safe = "Report";
        var path = Path.Combine(ReportRoot, $"{type}_{DateTime.Now:yyyyMMdd_HHmmss}_{safe}.md");
        await File.WriteAllTextAsync(path, content, new UTF8Encoding(false), cancellationToken).ConfigureAwait(false);
        return path;
    }

    private static string TypeFromName(string name)
        => name.StartsWith("GPU_", StringComparison.OrdinalIgnoreCase) ? "GPU / ReBAR" :
           name.StartsWith("DUMP_", StringComparison.OrdinalIgnoreCase) ? "Dump 分析" :
           name.StartsWith("REPAIR_", StringComparison.OrdinalIgnoreCase) ? "修复报告" :
           name.StartsWith("SYSTEM_", StringComparison.OrdinalIgnoreCase) ? "系统报告" : "报告";
}
