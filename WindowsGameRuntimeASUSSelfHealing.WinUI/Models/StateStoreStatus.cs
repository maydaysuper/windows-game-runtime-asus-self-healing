namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record StateStoreStatus(
    string DatabasePath,
    long DatabaseBytes,
    long CrashEventCount,
    long ComponentCount,
    long TransactionCount,
    long IncidentCount,
    long DumpAnalysisCount,
    string JournalMode,
    int SchemaVersion,
    DateTimeOffset? LastEventSyncUtc,
    string LastEventSyncError,
    string WorkflowState);
