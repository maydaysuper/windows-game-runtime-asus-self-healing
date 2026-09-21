using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class TransactionItem
{
    public string TransactionId { get; init; } = "";
    public string Type { get; init; } = "";
    public string Group { get; init; } = "";
    public string Label { get; init; } = "";
    public string State { get; init; } = "";
    public string StartedAt { get; init; } = "";
    public string UpdatedAt { get; init; } = "";
    public string LastDetail { get; init; } = "";
    public Brush StatusBrush => StatusPalette.Brush(State);
    public Brush StatusForeground => StatusPalette.Foreground(State);
}
