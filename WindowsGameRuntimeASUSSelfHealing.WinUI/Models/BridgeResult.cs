using System.Text.Json;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class BridgeResult : IDisposable
{
    public bool Success { get; init; }
    public string Action { get; init; } = "";
    public string Error { get; init; } = "";
    public JsonDocument? Document { get; init; }

    public JsonElement Payload
        => Document is not null && Document.RootElement.TryGetProperty("Payload", out var p)
            ? p
            : default;

    public void Dispose() => Document?.Dispose();
}
