using System.Collections.Concurrent;
using System.Diagnostics;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class PerformanceTracker
{
    private readonly ConcurrentDictionary<string, long> _lastDurations = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyDictionary<string, long> LastDurationsMs => _lastDurations;

    public async Task<T> MeasureAsync<T>(string operation, Func<Task<T>> action)
    {
        var stopwatch = Stopwatch.StartNew();
        try { return await action().ConfigureAwait(false); }
        finally
        {
            stopwatch.Stop();
            _lastDurations[operation] = stopwatch.ElapsedMilliseconds;
        }
    }

    public async Task MeasureAsync(string operation, Func<Task> action)
    {
        var stopwatch = Stopwatch.StartNew();
        try { await action().ConfigureAwait(false); }
        finally
        {
            stopwatch.Stop();
            _lastDurations[operation] = stopwatch.ElapsedMilliseconds;
        }
    }
}
