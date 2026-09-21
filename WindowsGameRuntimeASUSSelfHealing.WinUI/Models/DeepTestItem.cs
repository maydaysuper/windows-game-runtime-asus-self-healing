using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class DeepTestItem
{
    public string Category { get; init; } = "";
    public string Test { get; init; } = "";
    public string Status { get; init; } = "INFO";
    public string Detail { get; init; } = "";
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
