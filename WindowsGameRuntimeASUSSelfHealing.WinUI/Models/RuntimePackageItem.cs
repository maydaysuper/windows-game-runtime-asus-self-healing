using Microsoft.UI.Xaml.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class RuntimePackageItem
{
    public string Key { get; init; } = "";
    public string Version { get; init; } = "";
    public string Source { get; init; } = "";
    public string Sha256 { get; init; } = "";
    public string Signer { get; init; } = "";
    public string FinalUri { get; init; } = "";
    public bool Success { get; init; }
    public bool TrustComplete { get; init; }
    public string Status => Success && TrustComplete ? "PASS" : "WARN";
    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
