namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record BuildIdentity(
    string Version,
    string BuildId,
    string WindowsAppSdk,
    string DotNet,
    string Language,
    string EngineSha256,
    string BrokerSha256,
    string UiBridgeSha256,
    string EventReaderSha256,
    string GpuDiagnosticsReaderSha256,
    string GpuSafeRepairSha256,
    string AtomicPolicyExecutorSha256,
    string RecipeCatalogSha256,
    string BuildInfoSha256,
    string CapabilityBaselineSha256);
