namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class MemorySnapshot
{
    public ulong TotalBytes { get; init; }
    public ulong AvailBytes { get; init; }
    public uint LoadPercent { get; init; }
    public ulong UsedBytes => TotalBytes > AvailBytes ? TotalBytes - AvailBytes : 0;
    public string TotalText => FormatBytes(TotalBytes);
    public string AvailText => FormatBytes(AvailBytes);
    public string UsedText => FormatBytes(UsedBytes);
    public string Summary => $"已用 {LoadPercent}%（{UsedText} / {TotalText}）· 可用 {AvailText}";

    public static string FormatBytes(ulong bytes)
    {
        if (bytes >= 1024UL * 1024UL * 1024UL)
            return $"{bytes / 1024.0 / 1024.0 / 1024.0:0.0} GB";
        if (bytes >= 1024UL * 1024UL)
            return $"{bytes / 1024.0 / 1024.0:0.0} MB";
        return $"{bytes / 1024.0:0} KB";
    }
}

public sealed class MemoryCleanResult
{
    public required MemorySnapshot Before { get; init; }
    public required MemorySnapshot After { get; init; }
    public int ProcessesTrimmed { get; init; }
    public int ProcessesSkipped { get; init; }
    public long AvailDeltaBytes => (long)After.AvailBytes - (long)Before.AvailBytes;
    public string ResultLine
    {
        get
        {
            if (AvailDeltaBytes >= 1024 * 1024)
                return $"已把约 {MemorySnapshot.FormatBytes((ulong)AvailDeltaBytes)} 闲置内存还给系统。没有结束任何程序。";
            return "已整理工作集。正在运行的程序都还在，可用内存变化不大。";
        }
    }
}

public sealed class CacheBucket
{
    public required string Name { get; init; }
    public long Bytes { get; init; }
    public int Files { get; init; }
    public int Skipped { get; init; }
    public string Note { get; init; } = "";
    public string Line
    {
        get
        {
            var size = MemorySnapshot.FormatBytes((ulong)Math.Max(0, Bytes));
            var skip = Skipped > 0 ? $" · 跳过 {Skipped}" : "";
            return string.IsNullOrWhiteSpace(Note)
                ? $"{Name}：{size} / {Files} 个文件{skip}"
                : $"{Name}：{size} / {Files} 个文件{skip} · {Note}";
        }
    }
}

public sealed class CacheScanResult
{
    public IReadOnlyList<CacheBucket> Buckets { get; init; } = Array.Empty<CacheBucket>();
    public long TotalBytes { get; init; }
    public int TotalFiles { get; init; }
    public string Summary => TotalFiles == 0
        ? "现在没有多少可以安全清理的缓存。"
        : $"大约 {MemorySnapshot.FormatBytes((ulong)Math.Max(0, TotalBytes))}，{TotalFiles} 个文件。正在使用的会自动跳过。";
}

public sealed class CacheCleanResult
{
    public long BytesFreed { get; init; }
    public int FilesRemoved { get; init; }
    public int FilesSkipped { get; init; }
    public bool RecycleBinEmptied { get; init; }
    public bool DnsFlushed { get; init; }
    public IReadOnlyList<CacheBucket> Buckets { get; init; } = Array.Empty<CacheBucket>();
    public string ResultLine
    {
        get
        {
            var size = MemorySnapshot.FormatBytes((ulong)Math.Max(0, BytesFreed));
            var extra = RecycleBinEmptied ? "回收站已清空。" : "";
            if (DnsFlushed) extra += " DNS 缓存已刷新。";
            if (FilesRemoved == 0 && BytesFreed == 0)
                return "没有删到文件。正在使用的都已跳过。" + extra;
            return $"已清理 {size}，删除 {FilesRemoved} 个文件，跳过 {FilesSkipped} 个正在使用的文件。{extra}";
        }
    }
}

public sealed class RegistryCleanResult
{
    public int ItemsRemoved { get; init; }
    public int ItemsSkipped { get; init; }
    public IReadOnlyList<CacheBucket> Buckets { get; init; } = Array.Empty<CacheBucket>();
    public string ResultLine
    {
        get
        {
            if (ItemsRemoved == 0)
                return ItemsSkipped > 0
                    ? $"没有可删的残留。跳过 {ItemsSkipped} 项（受保护或无权修改）。"
                    : "没有发现可安全删除的注册表残留。";
            return $"已清理 {ItemsRemoved} 项无效残留，跳过 {ItemsSkipped} 项。没有改驱动、奥创中心和微软运行库。";
        }
    }
}
