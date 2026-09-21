namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record CrashTelemetrySnapshot(
    IReadOnlyList<CrashEventItem> Events,
    IReadOnlyList<string> GpuLines,
    IReadOnlyList<string> WerLines,
    int NewEventCount,
    DateTimeOffset SinceUtc,
    bool FromIncrementalCache,
    string Warning);
