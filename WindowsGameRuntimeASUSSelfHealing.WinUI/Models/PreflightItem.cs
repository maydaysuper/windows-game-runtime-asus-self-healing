using Microsoft.UI.Xaml.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class PreflightItem
{
    public string Name { get; init; } = "";
    public string Status { get; init; } = "INFO";
    public string Detail { get; init; } = "";
    public bool Blocking { get; init; }
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
