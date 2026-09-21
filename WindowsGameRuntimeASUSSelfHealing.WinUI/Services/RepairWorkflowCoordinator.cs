using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class RepairWorkflowCoordinator : IDisposable
{
    private readonly IStateStore _stateStore;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private RepairWorkflowSnapshot _current = new(
        RepairWorkflowPhase.Idle, "", "", false, "IDLE", "等待诊断", DateTimeOffset.UtcNow);
    private bool _initialized;

    public RepairWorkflowSnapshot Current => _current;

    public RepairWorkflowCoordinator(IStateStore stateStore) => _stateStore = stateStore;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        if (_initialized) return;
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_initialized) return;
            var persisted = await _stateStore.GetWorkflowAsync(cancellationToken).ConfigureAwait(false);
            if (persisted is not null) _current = persisted;
            _initialized = true;
        }
        finally
        {
            _gate.Release();
        }
    }

    public Task RecordDiagnosedAsync(string detail, CancellationToken cancellationToken = default)
        => TransitionAsync(RepairWorkflowPhase.Diagnosed, "", "", false, "DIAGNOSED", detail, cancellationToken, allowRestart: true, preserveActive: true);

    public Task RecordPlanAsync(string type, string group, string planState, bool eligible, string detail, CancellationToken cancellationToken = default)
    {
        var phase = eligible
            ? RepairWorkflowPhase.Eligible
            : planState == "NO_ACTION_REQUIRED"
                ? RepairWorkflowPhase.Planned
                : RepairWorkflowPhase.Blocked;
        return TransitionAsync(phase, type, group, eligible, planState, detail, cancellationToken);
    }

    public Task RecordBrokerStartAsync(string type, string group, CancellationToken cancellationToken = default)
        => TransitionAsync(
            RepairWorkflowPhase.BrokerRunning,
            type,
            group,
            true,
            "BROKER_RUNNING",
            "Elevated Broker 正在重新诊断并执行资格门禁",
            cancellationToken);

    public Task RecordBrokerResultAsync(
        string type,
        string group,
        bool success,
        string backendState,
        string detail,
        CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeState(backendState);
        var phase = MapBackendState(normalized, success);
        var eligible = success && phase is not RepairWorkflowPhase.Failed;
        return TransitionAsync(phase, type, group, eligible, normalized, detail, cancellationToken);
    }

    public Task RecordVerificationStartedAsync(CancellationToken cancellationToken = default)
        => TransitionAsync(
            RepairWorkflowPhase.VerificationRunning,
            _current.Type,
            _current.Group,
            _current.Eligible,
            "VERIFYING",
            "正在执行严格验证",
            cancellationToken,
            allowRestart: true);

    public Task RecordVerificationResultAsync(
        bool success,
        string backendState,
        string detail,
        CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeState(backendState);
        var phase = success ? MapBackendState(normalized, true) : RepairWorkflowPhase.Failed;
        if (success && phase == RepairWorkflowPhase.RepairCompleted) phase = RepairWorkflowPhase.Verified;
        return TransitionAsync(
            phase,
            _current.Type,
            _current.Group,
            success,
            normalized,
            detail,
            cancellationToken);
    }

    public Task RecordTransactionStateAsync(
        string type,
        string group,
        string state,
        string detail,
        CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeState(state);
        var phase = MapBackendState(normalized, !IsFailureState(normalized));
        return TransitionAsync(phase, type, group, !IsFailureState(normalized), normalized, detail, cancellationToken, allowRestart: true);
    }

    private async Task TransitionAsync(
        RepairWorkflowPhase phase,
        string type,
        string group,
        bool eligible,
        string state,
        string detail,
        CancellationToken cancellationToken,
        bool allowRestart = false,
        bool preserveActive = false)
    {
        await InitializeAsync(cancellationToken).ConfigureAwait(false);
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (preserveActive && IsActiveRepairPhase(_current.Phase)) return;
            if (!allowRestart && !CanTransition(_current.Phase, phase))
                throw new InvalidOperationException($"非法修复流程跳转：{_current.Phase} -> {phase}");

            _current = new RepairWorkflowSnapshot(
                phase,
                type,
                group,
                eligible,
                state,
                detail,
                DateTimeOffset.UtcNow);
            await _stateStore.RecordWorkflowAsync(_current, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    private static bool IsActiveRepairPhase(RepairWorkflowPhase phase)
        => phase is RepairWorkflowPhase.BrokerRunning
            or RepairWorkflowPhase.AwaitingReboot
            or RepairWorkflowPhase.RepairCompleted
            or RepairWorkflowPhase.VerificationRunning
            or RepairWorkflowPhase.Observing;

    private static bool CanTransition(RepairWorkflowPhase from, RepairWorkflowPhase to)
    {
        if (from == to) return true;
        if (to is RepairWorkflowPhase.Blocked or RepairWorkflowPhase.Failed) return true;
        return from switch
        {
            RepairWorkflowPhase.Idle => to is RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible,
            RepairWorkflowPhase.Diagnosed => to is RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible,
            RepairWorkflowPhase.Planned => to is RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Eligible,
            RepairWorkflowPhase.Eligible => to == RepairWorkflowPhase.BrokerRunning,
            RepairWorkflowPhase.BrokerRunning => to is RepairWorkflowPhase.AwaitingReboot or RepairWorkflowPhase.RepairCompleted or RepairWorkflowPhase.Observing or RepairWorkflowPhase.Verified,
            RepairWorkflowPhase.AwaitingReboot => to is RepairWorkflowPhase.BrokerRunning or RepairWorkflowPhase.RepairCompleted or RepairWorkflowPhase.VerificationRunning,
            RepairWorkflowPhase.RepairCompleted => to is RepairWorkflowPhase.VerificationRunning or RepairWorkflowPhase.Observing or RepairWorkflowPhase.Verified,
            RepairWorkflowPhase.VerificationRunning => to is RepairWorkflowPhase.Observing or RepairWorkflowPhase.Verified,
            RepairWorkflowPhase.Observing => to is RepairWorkflowPhase.Verified,
            RepairWorkflowPhase.Verified => to is RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible,
            RepairWorkflowPhase.Blocked => to is RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible,
            RepairWorkflowPhase.Failed => to is RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible,
            _ => false
        };
    }

    private static RepairWorkflowPhase MapBackendState(string state, bool success)
    {
        // A GUI wait timeout/cancellation does not mean the elevated transaction failed.
        // BrokerService deliberately leaves that process running so MSI/DISM work is never torn down.
        if (state is "BROKER_STILL_RUNNING" or "BROKER_WAIT_CANCELLED") return RepairWorkflowPhase.BrokerRunning;
        if (!success || IsFailureState(state)) return RepairWorkflowPhase.Failed;
        return state switch
        {
            "AWAITINGREBOOT" or "AWAITING_REBOOT" or "WAIT_REBOOT" => RepairWorkflowPhase.AwaitingReboot,
            "OBSERVING" => RepairWorkflowPhase.Observing,
            "COMPLETED" or "VERIFIED" => RepairWorkflowPhase.Verified,
            "SUCCESSPENDINGVERIFICATION" or "SUCCESS_PENDING_VERIFICATION" or "NEEDSVERIFICATION" or "NEEDS_VERIFICATION" => RepairWorkflowPhase.RepairCompleted,
            "POSTREBOOTSTARTED" or "POST_REBOOT_STARTED" or "MODULEEXECUTING" or "MODULE_EXECUTING" or "REPAIRSTARTED" or "REPAIR_STARTED" => RepairWorkflowPhase.BrokerRunning,
            _ => RepairWorkflowPhase.RepairCompleted
        };
    }

    private static bool IsFailureState(string state)
        => state.Contains("FAIL", StringComparison.OrdinalIgnoreCase)
           || state.Contains("NEEDSATTENTION", StringComparison.OrdinalIgnoreCase)
           || state.Contains("NEEDS_ATTENTION", StringComparison.OrdinalIgnoreCase)
           || state.Contains("CANCEL", StringComparison.OrdinalIgnoreCase)
           || state.Contains("BLOCK", StringComparison.OrdinalIgnoreCase);

    private static string NormalizeState(string state)
        => string.IsNullOrWhiteSpace(state) ? "UNKNOWN" : state.Trim().ToUpperInvariant();

    public void Dispose() => _gate.Dispose();
}
