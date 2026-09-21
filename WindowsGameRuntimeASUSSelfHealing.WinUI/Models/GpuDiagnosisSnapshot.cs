using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record GpuDiagnosisSnapshot
{
    public string PrimaryCauseCode { get; init; } = "EVIDENCE_INSUFFICIENT";
    public string PrimaryCauseTitle { get; init; } = "证据不足";
    public string Confidence { get; init; } = "LOW";
    public string Summary { get; init; } = "";
    public string RebarStatus { get; init; } = "UNKNOWN";
    public string RebarEvidence { get; init; } = "";
    public string MemorySummary { get; init; } = "";
    public string EventSummary { get; init; } = "";
    public string DumpSummary { get; init; } = "";
    public IReadOnlyList<string> Evidence { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> RepairPlan { get; init; } = Array.Empty<string>();
    public bool SafeAutoRepairAvailable { get; init; }
    public string SafeAutoRepairLabel { get; init; } = "";
    public string ReportPath { get; init; } = "";
    public DateTimeOffset AnalyzedUtc { get; init; } = DateTimeOffset.UtcNow;

    public string Status => Confidence.Equals("HIGH", StringComparison.OrdinalIgnoreCase) ? "FAIL" :
        Confidence.Equals("MEDIUM", StringComparison.OrdinalIgnoreCase) ? "WARN" : "INFO";
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
    public string EvidenceText => Evidence.Count == 0 ? "无" : string.Join("\n", Evidence.Select(x => "• " + x));
    public string RepairPlanText => RepairPlan.Count == 0 ? "当前没有可安全自动执行的修复。" : string.Join("\n", RepairPlan.Select(x => "• " + x));
    public string AnalyzedText => AnalyzedUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
}
