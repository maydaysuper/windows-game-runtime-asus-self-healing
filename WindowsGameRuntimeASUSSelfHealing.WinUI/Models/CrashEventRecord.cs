namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record CrashEventRecord(
    string EventKey,
    DateTimeOffset OccurredUtc,
    string LogName,
    long RecordId,
    string Category,
    string Severity,
    string Provider,
    int EventId,
    string ProcessName,
    string Message);
