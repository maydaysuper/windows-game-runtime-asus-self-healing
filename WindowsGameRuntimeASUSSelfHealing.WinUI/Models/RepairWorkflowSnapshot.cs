namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public enum RepairWorkflowPhase
{
    Idle = 0,
    Diagnosed = 10,
    Planned = 20,
    Eligible = 30,
    BrokerRunning = 40,
    AwaitingReboot = 45,
    RepairCompleted = 50,
    VerificationRunning = 60,
    Observing = 70,
    Verified = 80,
    Blocked = 90,
    Failed = 100
}

public sealed record RepairWorkflowSnapshot(
    RepairWorkflowPhase Phase,
    string Type,
    string Group,
    bool Eligible,
    string State,
    string Detail,
    DateTimeOffset UpdatedUtc);
