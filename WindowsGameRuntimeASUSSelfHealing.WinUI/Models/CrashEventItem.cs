using Microsoft.UI.Xaml.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class CrashEventItem
{
    public string Time { get; init; } = "";
    public string Category { get; init; } = "";
    public string Severity { get; init; } = "WARN";
    public string Process { get; init; } = "";
    public int Count { get; init; } = 1;
    public string Provider { get; init; } = "";
    public int Id { get; init; }
    public string Message { get; init; } = "";
    public string CountText => Count > 1 ? $"×{Count}" : "1";
    public string ProviderText => $"{Provider} / {Id}";
    public Brush StatusBrush => StatusPalette.Brush(Severity);
    public Brush StatusForeground => StatusPalette.Foreground(Severity);
}
