using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class ComponentItem
{
    public string Key { get; init; } = "";
    public string Name { get; init; } = "";
    public string Installed { get; init; } = "";
    public string Target { get; init; } = "";
    public string Runtime { get; init; } = "";
    public string ErrorCode { get; init; } = "";
    public string Status { get; init; } = "INFO";
    public string Detail { get; init; } = "";
    public string Group { get; init; } = "";
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
