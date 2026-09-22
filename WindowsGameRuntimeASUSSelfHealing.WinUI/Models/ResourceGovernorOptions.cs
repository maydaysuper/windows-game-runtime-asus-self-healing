using System.Text.Json;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class ResourceGovernorOptions
{
    public int MaxConcurrentJobs { get; init; }
    public int MaxMemoryMB { get; init; }
    public int MaxCpuPercent { get; init; }

    public static ResourceGovernorOptions Load()
    {
        foreach (var dir in new[] { StartupGuard.HostDirectory, AppContext.BaseDirectory })
        {
            if (string.IsNullOrWhiteSpace(dir)) continue;
            var path = Path.Combine(dir, "appsettings.json");
            try
            {
                if (!File.Exists(path)) continue;
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                if (!doc.RootElement.TryGetProperty("ResourceGovernor", out var section)) continue;
                return new ResourceGovernorOptions
                {
                    MaxConcurrentJobs = ReadInt(section, "MaxConcurrentJobs"),
                    MaxMemoryMB = ReadInt(section, "MaxMemoryMB"),
                    MaxCpuPercent = ReadInt(section, "MaxCpuPercent")
                };
            }
            catch
            {
                // Keep auto-detected limits if the optional config file is missing or invalid.
            }
        }
        return new ResourceGovernorOptions();
    }

    private static int ReadInt(JsonElement section, string name)
        => section.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetInt32()
            : 0;
}
