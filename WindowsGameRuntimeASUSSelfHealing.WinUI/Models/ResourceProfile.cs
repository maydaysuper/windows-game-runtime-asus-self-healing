namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record ResourceProfile(
    string Name,
    int LogicalProcessors,
    long AvailableMemoryBytes,
    int MaxBackgroundOperations,
    bool PreferBelowNormalPriority)
{
    public string MemoryText => AvailableMemoryBytes <= 0
        ? "未知"
        : $"{AvailableMemoryBytes / (1024d * 1024d * 1024d):0.0} GB";
}
