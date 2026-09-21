namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed record BrokerExecutionResult(
    bool Success,
    string Detail,
    string State,
    string TransactionId);
