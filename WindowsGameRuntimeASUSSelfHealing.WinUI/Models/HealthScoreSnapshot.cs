namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record HealthScoreSnapshot(
    int Score,
    string State,
    string Summary,
    string AsusState,
    string AsusSummary,
    string RuntimeState,
    string RuntimeSummary,
    string CrashState,
    string CrashSummary,
    string SystemState,
    string SystemSummary);
