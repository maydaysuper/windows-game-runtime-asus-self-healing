using System.Text.Json;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

public interface IStateStore
{
    string DatabasePath { get; }
    Task InitializeAsync(CancellationToken cancellationToken = default);
    Task<DateTimeOffset?> GetEventCursorAsync(string stream, CancellationToken cancellationToken = default);
    Task SetEventCursorAsync(string stream, DateTimeOffset cursorUtc, CancellationToken cancellationToken = default);
    Task RecordEventSyncAsync(string stream, DateTimeOffset attemptedUtc, bool success, int newEventCount, string error = "", CancellationToken cancellationToken = default);
    Task<int> UpsertCrashEventsAsync(IEnumerable<CrashEventRecord> events, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<CrashEventItem>> ReadCrashEventGroupsAsync(int days = 7, int maxEvents = 120, CancellationToken cancellationToken = default);
    Task SaveDumpAnalysisAsync(DumpAnalysisResult result, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<DumpAnalysisResult>> ReadDumpAnalysesAsync(int maxItems = 30, CancellationToken cancellationToken = default);
    Task UpsertComponentStatesAsync(IEnumerable<ComponentItem> items, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ComponentItem>> ReadComponentStatesAsync(string group = "", CancellationToken cancellationToken = default);
    Task UpsertTransactionsAsync(IEnumerable<TransactionItem> items, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<TransactionItem>> ReadTransactionsAsync(int maxTransactions = 50, CancellationToken cancellationToken = default);
    Task UpsertIncidentsAsync(IEnumerable<JsonElement> incidents, CancellationToken cancellationToken = default);
    Task RecordWorkflowAsync(RepairWorkflowSnapshot snapshot, CancellationToken cancellationToken = default);
    Task<RepairWorkflowSnapshot?> GetWorkflowAsync(CancellationToken cancellationToken = default);
    Task<StateStoreStatus> GetStatusAsync(CancellationToken cancellationToken = default);
    Task PruneAsync(CancellationToken cancellationToken = default);
    Task ClearVolatileCacheAsync(CancellationToken cancellationToken = default);
}
