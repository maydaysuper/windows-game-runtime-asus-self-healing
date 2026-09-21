namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record GpuMemoryAdapterSnapshot
{
    public string Name { get; init; } = "";
    public string Luid { get; init; } = "";
    public long DedicatedLimitBytes { get; init; }
    public long DedicatedUsageBytes { get; init; }
    public long DedicatedPeakBytes { get; init; }
    public long SharedUsageBytes { get; init; }
    public long SharedPeakBytes { get; init; }

    public double DedicatedPressurePercent => DedicatedLimitBytes <= 0 ? 0 : Math.Clamp(DedicatedPeakBytes * 100d / DedicatedLimitBytes, 0, 999);
    public string DedicatedPressureText => DedicatedLimitBytes <= 0 ? "未知" : $"{DedicatedPressurePercent:0.0}%";
    public string DedicatedText => $"{FormatBytes(DedicatedPeakBytes)} / {FormatBytes(DedicatedLimitBytes)}";
    public string SharedText => FormatBytes(SharedPeakBytes);

    public static string FormatBytes(long value) => value switch
    {
        >= 1024L * 1024L * 1024L => $"{value / (1024d * 1024d * 1024d):0.00} GB",
        >= 1024L * 1024L => $"{value / (1024d * 1024d):0.0} MB",
        >= 1024L => $"{value / 1024d:0.0} KB",
        _ => $"{Math.Max(0, value)} B"
    };
}

public sealed record GpuMemorySnapshot(
    IReadOnlyList<GpuMemoryAdapterSnapshot> Adapters,
    bool CountersAvailable,
    string Warning,
    DateTimeOffset CapturedUtc)
{
    public GpuMemoryAdapterSnapshot? PrimaryAdapter => Adapters
        .OrderByDescending(x => x.DedicatedLimitBytes)
        .FirstOrDefault();
}
