using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public sealed class AppServices : IDisposable
{
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

    public AppServices()
    {
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
    }

    public void Dispose()
    {
        CrashTelemetry.Dispose();
        GpuDiagnostics.Dispose();
        Broker.Dispose();
        Backend.Dispose();
        StateStore.Dispose();
        Resources.Dispose();
    }
}
