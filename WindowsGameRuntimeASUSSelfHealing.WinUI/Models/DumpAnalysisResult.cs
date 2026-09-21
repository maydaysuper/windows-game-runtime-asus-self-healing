using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record DumpAnalysisResult
{
    public string Id { get; init; } = Guid.NewGuid().ToString("N");
    public string FileName { get; init; } = "";
    public string FilePath { get; init; } = "";
    public long FileSizeBytes { get; init; }
    public string ExceptionCode { get; init; } = "";
    public string ExceptionName { get; init; } = "";
    public string ExceptionAddress { get; init; } = "";
    public string FaultingModule { get; init; } = "";
    public string Category { get; init; } = "UNKNOWN";
    public string Confidence { get; init; } = "LOW";
    public string CoreReason { get; init; } = "";
    public string Evidence { get; init; } = "";
    public DateTimeOffset AnalyzedUtc { get; init; } = DateTimeOffset.UtcNow;
    public string ReportPath { get; init; } = "";

    public string FileSizeText => FileSizeBytes switch
    {
        >= 1024L * 1024L * 1024L => $"{FileSizeBytes / (1024d * 1024d * 1024d):0.00} GB",
        >= 1024L * 1024L => $"{FileSizeBytes / (1024d * 1024d):0.0} MB",
        >= 1024L => $"{FileSizeBytes / 1024d:0.0} KB",
        _ => $"{FileSizeBytes} B"
    };
    public string AnalyzedText => AnalyzedUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
    public string Status => Confidence.Equals("HIGH", StringComparison.OrdinalIgnoreCase) ? "PASS" :
        Confidence.Equals("MEDIUM", StringComparison.OrdinalIgnoreCase) ? "WARN" : "INFO";
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
