using System.Text.Json;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public static class JsonHelpers
{
    public static string String(this JsonElement element, string name)
        => element.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null ? v.ToString() : "";

    public static bool Bool(this JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var v)) return false;
        return v.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Number => v.TryGetInt64(out var n) && n != 0 || v.TryGetDouble(out var d) && Math.Abs(d) > double.Epsilon,
            JsonValueKind.String => IsTruthy(v.GetString()),
            _ => false
        };
    }

    public static int Int(this JsonElement element, string name, int fallback = 0)
        => element.TryGetProperty(name, out var v) && v.TryGetInt32(out var i) ? i : fallback;

    public static long Long(this JsonElement element, string name, long fallback = 0)
        => element.TryGetProperty(name, out var v) && v.TryGetInt64(out var i) ? i : fallback;

    public static IEnumerable<JsonElement> Array(this JsonElement element, string name)
    {
        if (element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Array)
            foreach (var item in v.EnumerateArray()) yield return item;
    }

    public static string[] StringArray(this JsonElement element, string name)
    {
        var list = new List<string>();
        foreach (var item in element.Array(name))
        {
            if (item.ValueKind == JsonValueKind.Null) continue;
            var s = item.ValueKind == JsonValueKind.String ? item.GetString() : item.ToString();
            if (!string.IsNullOrWhiteSpace(s)) list.Add(s.Trim());
        }
        return list.ToArray();
    }

    private static bool IsTruthy(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return false;
        return value.Equals("true", StringComparison.OrdinalIgnoreCase)
            || value.Equals("yes", StringComparison.OrdinalIgnoreCase)
            || value.Equals("1", StringComparison.OrdinalIgnoreCase);
    }
}
