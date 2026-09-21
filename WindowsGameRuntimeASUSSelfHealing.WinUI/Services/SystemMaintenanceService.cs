using System.Diagnostics;
using System.Runtime.InteropServices;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

/// <summary>
/// Safe cache/memory tools. Never kills processes, never touches shader caches,
/// dumps, drivers, BIOS, or Armoury repair state.
/// </summary>
public sealed class SystemMaintenanceService
{
    private static readonly HashSet<string> ProtectedProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "Idle", "System", "Registry", "smss", "csrss", "wininit", "lsass",
        "winlogon", "Memory Compression", "Secure System", "LsaIso"
    };

    private static readonly string[] ForbiddenPathParts =
    {
        "shader", "dxcache", "d3dscache", "glcache", "nv_cache", "nvcache",
        "livekernel", "minidump", "crashdumps", "windows\\prefetch",
        "windows\\fonts", "softwaredistribution\\download",
        "windowsruntimeasusselfhealing\\state",
        "windowsruntimeasusselfhealing\\backend"
    };

    private const int ProcessQueryLimitedInformation = 0x1000;
    private const int ProcessSetQuota = 0x0100;
    private const uint SherbNoConfirmation = 0x00000001;
    private const uint SherbNoProgressUi = 0x00000002;
    private const uint SherbNoSound = 0x00000004;

    public MemorySnapshot ReadMemory()
    {
        var status = new MemoryStatusEx { Length = (uint)Marshal.SizeOf<MemoryStatusEx>() };
        if (!GlobalMemoryStatusEx(ref status))
            throw new InvalidOperationException("无法读取内存状态。");
        return new MemorySnapshot
        {
            TotalBytes = status.TotalPhys,
            AvailBytes = status.AvailPhys,
            LoadPercent = status.MemoryLoad
        };
    }

    public Task<MemoryCleanResult> CleanMemoryAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => CleanMemory(cancellationToken), cancellationToken);

    public Task<CacheScanResult> ScanCacheAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => ScanCache(cancellationToken), cancellationToken);

    public Task<CacheCleanResult> CleanCacheAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => CleanCache(cancellationToken), cancellationToken);

    private MemoryCleanResult CleanMemory(CancellationToken cancellationToken)
    {
        var before = ReadMemory();
        var trimmed = 0;
        var skipped = 0;
        var self = Process.GetCurrentProcess().Id;
        foreach (var process in Process.GetProcesses())
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (process.Id <= 4 || process.Id == self || ProtectedProcessNames.Contains(process.ProcessName))
                {
                    skipped++;
                    continue;
                }
                var handle = OpenProcess(ProcessQueryLimitedInformation | ProcessSetQuota, false, process.Id);
                if (handle == IntPtr.Zero)
                {
                    skipped++;
                    continue;
                }
                try
                {
                    if (EmptyWorkingSet(handle) != 0) trimmed++;
                    else skipped++;
                }
                finally { CloseHandle(handle); }
            }
            catch
            {
                skipped++;
            }
            finally { process.Dispose(); }
        }

        try
        {
            var selfHandle = Process.GetCurrentProcess().Handle;
            EmptyWorkingSet(selfHandle);
        }
        catch { }

        Thread.Sleep(200);
        var after = ReadMemory();
        return new MemoryCleanResult
        {
            Before = before,
            After = after,
            ProcessesTrimmed = trimmed,
            ProcessesSkipped = skipped
        };
    }

    private CacheScanResult ScanCache(CancellationToken cancellationToken)
    {
        var buckets = CollectBuckets(delete: false, cancellationToken);
        return new CacheScanResult
        {
            Buckets = buckets,
            TotalBytes = buckets.Sum(b => b.Bytes),
            TotalFiles = buckets.Sum(b => b.Files)
        };
    }

    private CacheCleanResult CleanCache(CancellationToken cancellationToken)
    {
        var buckets = CollectBuckets(delete: true, cancellationToken);
        var recycle = TryEmptyRecycleBin();
        var dns = TryFlushDns();
        return new CacheCleanResult
        {
            BytesFreed = buckets.Sum(b => b.Bytes),
            FilesRemoved = buckets.Sum(b => b.Files),
            FilesSkipped = buckets.Sum(b => b.Skipped),
            RecycleBinEmptied = recycle,
            DnsFlushed = dns,
            Buckets = buckets
        };
    }

    private List<CacheBucket> CollectBuckets(bool delete, CancellationToken cancellationToken)
    {
        var list = new List<CacheBucket>();
        var userTemp = Path.GetTempPath();
        list.Add(Walk("用户临时文件", userTemp, delete, cancellationToken));

        var winTemp = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Temp");
        if (!PathsEqual(winTemp, userTemp))
            list.Add(Walk("Windows 临时文件", winTemp, delete, cancellationToken, optional: true));

        var explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "Explorer");
        list.Add(Walk("缩略图缓存", explorer, delete, cancellationToken, filePredicate: name =>
            name.StartsWith("thumbcache_", StringComparison.OrdinalIgnoreCase) ||
            name.StartsWith("iconcache_", StringComparison.OrdinalIgnoreCase)));

        var wer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Windows", "WER", "ReportQueue");
        list.Add(Walk("错误报告队列", wer, delete, cancellationToken, optional: true));

        var recycle = QueryRecycleBin();
        list.Add(new CacheBucket
        {
            Name = "回收站",
            Bytes = recycle.bytes,
            Files = recycle.items,
            Note = "清理时会清空，不会结束正在运行的程序"
        });
        return list;
    }

    private CacheBucket Walk(string name, string root, bool delete, CancellationToken cancellationToken, bool optional = false, Func<string, bool>? filePredicate = null)
    {
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
            return new CacheBucket { Name = name, Note = optional ? "当前没有或无权访问" : "目录不存在" };

        long bytes = 0;
        var files = 0;
        var skipped = 0;
        var cutoff = DateTime.UtcNow.AddMinutes(-5);
        EnumerationOptions options;
        try
        {
            options = new EnumerationOptions
            {
                RecurseSubdirectories = true,
                IgnoreInaccessible = true,
                ReturnSpecialDirectories = false,
                AttributesToSkip = FileAttributes.ReparsePoint,
                MaxRecursionDepth = 8
            };
        }
        catch
        {
            options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true };
        }

        IEnumerable<string> paths;
        try { paths = Directory.EnumerateFiles(root, "*", options); }
        catch (Exception ex) { return new CacheBucket { Name = name, Note = "跳过：" + ex.Message }; }

        foreach (var path in paths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (files + skipped > 25000) break;
            var fileName = Path.GetFileName(path);
            if (filePredicate is not null && !filePredicate(fileName)) continue;
            if (IsForbidden(path)) { skipped++; continue; }
            try
            {
                var info = new FileInfo(path);
                if ((info.Attributes & FileAttributes.System) != 0) { skipped++; continue; }
                if (info.LastWriteTimeUtc > cutoff) { skipped++; continue; }
                var size = info.Length;
                if (delete)
                {
                    info.IsReadOnly = false;
                    info.Delete();
                }
                bytes += size;
                files++;
            }
            catch
            {
                skipped++;
            }
        }

        return new CacheBucket { Name = name, Bytes = bytes, Files = files, Skipped = skipped };
    }

    private static bool IsForbidden(string path)
    {
        var lower = path.Replace('/', '\\').ToLowerInvariant();
        foreach (var part in ForbiddenPathParts)
        {
            if (lower.Contains(part, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    private static bool PathsEqual(string a, string b)
    {
        try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }

    private static (long bytes, int items) QueryRecycleBin()
    {
        try
        {
            var info = new ShQueryRbInfo { Size = Marshal.SizeOf<ShQueryRbInfo>() };
            if (SHQueryRecycleBin(null, ref info) == 0)
                return (info.SizeBytes, (int)Math.Min(int.MaxValue, info.NumItems));
        }
        catch { }
        return (0, 0);
    }

    private static bool TryEmptyRecycleBin()
    {
        try { return SHEmptyRecycleBin(IntPtr.Zero, null, SherbNoConfirmation | SherbNoProgressUi | SherbNoSound) == 0; }
        catch { return false; }
    }

    private static bool TryFlushDns()
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo
            {
                FileName = "ipconfig",
                Arguments = "/flushdns",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (p is null) return false;
            p.WaitForExit(8000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ShQueryRbInfo
    {
        public int Size;
        public long SizeBytes;
        public long NumItems;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);

    [DllImport("psapi.dll")]
    private static extern int EmptyWorkingSet(IntPtr hProcess);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(int access, [MarshalAs(UnmanagedType.Bool)] bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHEmptyRecycleBin(IntPtr hwnd, string? root, uint flags);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHQueryRecycleBin(string? root, ref ShQueryRbInfo info);
}
