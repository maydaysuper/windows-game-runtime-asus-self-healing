using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public sealed class AppServices : IDisposable
{
    public SessionLogService SessionLog { get; }
    public AdaptiveResourceGovernor Resources { get; }
    public BackendService Backend { get; }
    public StateStoreService StateStore { get; }
    public BrokerService Broker { get; }
    public CrashTelemetryService CrashTelemetry { get; }
    public RepairWorkflowCoordinator Workflow { get; }
    public PerformanceTracker Performance { get; }
    public HealthScoreService HealthScore { get; }
    public DumpAnalysisService DumpAnalysis { get; }
    public GpuMemoryTelemetryService GpuMemoryTelemetry { get; }
    public GpuDiagnosticsService GpuDiagnostics { get; }
    public ReportService Reports { get; }
    public SystemMaintenanceService Maintenance { get; }

    public AppServices()
    {
        SessionLog = new SessionLogService();
        Resources = new AdaptiveResourceGovernor();
        StateStore = new StateStoreService();
        Backend = new BackendService(Resources);
        Broker = new BrokerService(Backend);
        CrashTelemetry = new CrashTelemetryService(Backend, StateStore);
        Workflow = new RepairWorkflowCoordinator(StateStore);
        Performance = new PerformanceTracker();
        HealthScore = new HealthScoreService();
        DumpAnalysis = new DumpAnalysisService(Resources);
        GpuMemoryTelemetry = new GpuMemoryTelemetryService(Resources);
        GpuDiagnostics = new GpuDiagnosticsService(Backend, StateStore, GpuMemoryTelemetry, DumpAnalysis);
        Reports = new ReportService(Backend, StateStore, HealthScore);
        Maintenance = new SystemMaintenanceService();
    }

    public void Dispose()
    {
        try { CrashTelemetry.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.CrashTelemetry", ex); }
        try { GpuDiagnostics.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.GpuDiagnostics", ex); }
        try { Broker.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.Broker", ex); }
        try { Backend.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.Backend", ex); }
        try { StateStore.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.StateStore", ex); }
        try { Resources.Dispose(); } catch (Exception ex) { SessionLog.Bug("Dispose.Resources", ex); }
        SessionLog.Flush();
    }
}
