using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public static class StatusPalette
{
    public static Brush Brush(string? status) => new SolidColorBrush(ColorFor(status));
    public static Color ColorFor(string? status) => (status ?? string.Empty).ToUpperInvariant() switch
    {
        "PASS" or "HEALTHY" or "COMPLETED" => Color.FromRgb(220, 252, 231),
        "REPAIR" or "FAIL" or "BLOCK" or "BLOCKED" or "NEEDS_REPAIR" => Color.FromRgb(254, 226, 226),
        "WARN" or "MANUAL" or "WAIT_REBOOT" or "BUSY" or "MANUAL_ONLY" or "ATTENTION" => Color.FromRgb(254, 243, 199),
        "UPDATE" or "ELIGIBLE" or "INFO" => Color.FromRgb(219, 234, 254),
        _ => Color.FromRgb(241, 245, 249),
    };

    public static Brush Foreground(string? status) => new SolidColorBrush((status ?? string.Empty).ToUpperInvariant() switch
    {
        "PASS" or "HEALTHY" or "COMPLETED" => Color.FromRgb(22, 101, 52),
        "REPAIR" or "FAIL" or "BLOCK" or "BLOCKED" or "NEEDS_REPAIR" => Color.FromRgb(153, 27, 27),
        "WARN" or "MANUAL" or "WAIT_REBOOT" or "BUSY" or "MANUAL_ONLY" or "ATTENTION" => Color.FromRgb(146, 64, 14),
        "UPDATE" or "ELIGIBLE" or "INFO" => Color.FromRgb(30, 64, 175),
        _ => Color.FromRgb(100, 116, 139),
    });
}
