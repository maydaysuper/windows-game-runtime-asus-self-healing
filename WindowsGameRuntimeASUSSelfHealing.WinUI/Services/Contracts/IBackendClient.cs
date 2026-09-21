using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

public interface IBackendClient
{
    BuildIdentity GetBuildIdentity();

    Task<BridgeResult> RunAsync(
        string action,
        string? group = null,
        string? exeName = null,
        bool force = false,
        string? sinceUtc = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default);
}
