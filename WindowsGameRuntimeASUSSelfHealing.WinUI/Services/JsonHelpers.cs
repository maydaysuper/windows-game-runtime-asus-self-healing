using System.Text.Json;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public static class JsonHelpers
{
    public static string String(this JsonElement element, string name)
        => element.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null ? v.ToString() : "";

    public static bool Bool(this JsonElement element, string name)
        => element.TryGetProperty(name, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False && v.GetBoolean();

    public static int Int(this JsonElement element, string name, int fallback = 0)
        => element.TryGetProperty(name, out var v) && v.TryGetInt32(out var i) ? i : fallback;

    public static long Long(this JsonElement element, string name, long fallback = 0)
        => element.TryGetProperty(name, out var v) && v.TryGetInt64(out var i) ? i : fallback;

    public static IEnumerable<JsonElement> Array(this JsonElement element, string name)
    {
        if (element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Array)
            foreach (var item in v.EnumerateArray()) yield return item;
    }
}
