using System.Globalization;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class CrashTelemetryService : IDisposable
{
    private const string CursorName = "crash-eventlog-v1";
    private static readonly TimeSpan CursorOverlap = TimeSpan.FromMinutes(2);
    private readonly IBackendClient _backend;
    private readonly IStateStore _stateStore;
    private readonly SemaphoreSlim _refreshGate = new(1, 1);

    public CrashTelemetryService(IBackendClient backend, IStateStore stateStore)
    {
        _backend = backend;
        _stateStore = stateStore;
    }

    public async Task<CrashTelemetrySnapshot> RefreshAsync(bool force = false, CancellationToken cancellationToken = default)
    {
        await _refreshGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        var attemptedUtc = DateTimeOffset.UtcNow;
        try
        {
            await _stateStore.InitializeAsync(cancellationToken).ConfigureAwait(false);
            var cursor = force ? null : await _stateStore.GetEventCursorAsync(CursorName, cancellationToken).ConfigureAwait(false);
            var since = cursor.HasValue
                ? cursor.Value.Subtract(CursorOverlap)
                : DateTimeOffset.UtcNow.AddDays(-7);

            try
            {
                using var result = await _backend.RunAsync(
                    "CRASH_DELTA",
                    force: force,
                    sinceUtc: since.ToUniversalTime().ToString("O"),
                    timeout: TimeSpan.FromMinutes(2),
                    cancellationToken: cancellationToken).ConfigureAwait(false);

                if (!result.Success)
                    throw new InvalidOperationException(result.Error);

                var rawEvents = new List<CrashEventRecord>();
                foreach (var item in result.Payload.Array("Events"))
                {
                    var rawTime = item.String("Time");
                    if (!DateTimeOffset.TryParse(rawTime, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var occurred))
                        continue;
                    var logName = item.String("LogName");
                    var recordId = item.Long("RecordId");
                    var eventKey = item.String("EventKey");
                    if (string.IsNullOrWhiteSpace(eventKey)) eventKey = $"{logName}:{recordId}";
                    if (string.IsNullOrWhiteSpace(logName) || recordId <= 0 || string.IsNullOrWhiteSpace(eventKey))
                        continue;

                    rawEvents.Add(new CrashEventRecord(
                        eventKey,
                        occurred,
                        logName,
                        recordId,
                        item.String("Category"),
                        item.String("Severity"),
                        item.String("Provider"),
                        item.Int("Id"),
                        item.String("Process"),
                        item.String("Message")));
                }

                var inserted = await _stateStore.UpsertCrashEventsAsync(rawEvents, cancellationToken).ConfigureAwait(false);

                // Advance to the scan's captured upper bound, not merely to the newest matching event.
                // With the overlap this is both gap-safe and efficient on machines with no recent crashes.
                var scanStarted = ParseUtc(result.Payload.String("ScanStartedUtc")) ?? attemptedUtc;
                await _stateStore.SetEventCursorAsync(CursorName, scanStarted, cancellationToken).ConfigureAwait(false);
                await _stateStore.RecordEventSyncAsync(CursorName, attemptedUtc, true, inserted, cancellationToken: cancellationToken).ConfigureAwait(false);

                await _stateStore.PruneAsync(cancellationToken).ConfigureAwait(false);
                var grouped = await _stateStore.ReadCrashEventGroupsAsync(7, 120, cancellationToken).ConfigureAwait(false);
                var gpu = result.Payload.Array("GPU")
                    .Select(g => $"[{g.String("Status")}] {g.String("Test")}\n{g.String("Detail")}")
                    .ToArray();
                var wer = result.Payload.Array("WER")
                    .Select(w => $"{w.String("Exe")} | folder={w.String("DumpFolder")} | count={w.String("DumpCount")} | type={w.String("DumpType")}")
                    .ToArray();

                return new CrashTelemetrySnapshot(grouped, gpu, wer, inserted, since, false, "");
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                await _stateStore.RecordEventSyncAsync(CursorName, attemptedUtc, false, 0, ex.Message, cancellationToken).ConfigureAwait(false);
                var cached = await _stateStore.ReadCrashEventGroupsAsync(7, 120, cancellationToken).ConfigureAwait(false);
                if (cached.Count == 0) throw;
                return new CrashTelemetrySnapshot(
                    cached,
                    Array.Empty<string>(),
                    Array.Empty<string>(),
                    0,
                    since,
                    true,
                    "实时事件增量读取失败，当前显示 SQLite 最近缓存：" + ex.Message);
            }
        }
        finally
        {
            _refreshGate.Release();
        }
    }

    private static DateTimeOffset? ParseUtc(string value)
        => DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)
            ? parsed.ToUniversalTime()
            : null;

    public void Dispose() => _refreshGate.Dispose();
}
