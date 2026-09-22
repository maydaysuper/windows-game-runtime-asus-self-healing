using System.Diagnostics;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class AdaptiveResourceGovernor : IDisposable
{
    private readonly SemaphoreSlim _backgroundGate;
    public ResourceProfile Profile { get; }
    public ResourceGovernorOptions Options { get; }

    public AdaptiveResourceGovernor(ResourceGovernorOptions? options = null)
    {
        Options = options ?? ResourceGovernorOptions.Load();
        var cores = Math.Max(1, Environment.ProcessorCount);
        var available = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes;
        if (available <= 0) available = 8L * 1024 * 1024 * 1024;

        var low = cores <= 4 || available <= 8L * 1024 * 1024 * 1024;
        var high = cores >= 12 && available >= 24L * 1024 * 1024 * 1024;
        var autoMax = low ? 1 : 2;
        var max = Options.MaxConcurrentJobs > 0 ? Math.Clamp(Options.MaxConcurrentJobs, 1, 4) : autoMax;
        if (Options.MaxMemoryMB > 0 && available > Options.MaxMemoryMB * 1024L * 1024L)
            available = Options.MaxMemoryMB * 1024L * 1024L;
        Profile = new ResourceProfile(low ? "节能" : high ? "高性能设备 / 受控并发" : "均衡", cores, available, max, low);
        _backgroundGate = new SemaphoreSlim(max, max);
    }

    public async Task<IDisposable> EnterBackgroundWorkAsync(CancellationToken cancellationToken = default)
    {
        await _backgroundGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        return new Releaser(_backgroundGate);
    }

    public void TuneChildProcess(Process process, bool telemetryOnly)
    {
        try
        {
            if (telemetryOnly || Profile.PreferBelowNormalPriority)
                process.PriorityClass = ProcessPriorityClass.BelowNormal;
        }
        catch { }
    }


    public void Dispose() => _backgroundGate.Dispose();

    private sealed class Releaser : IDisposable
    {
        private SemaphoreSlim? _gate;
        public Releaser(SemaphoreSlim gate) => _gate = gate;
        public void Dispose() => Interlocked.Exchange(ref _gate, null)?.Release();
    }
}
