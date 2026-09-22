using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

/// <summary>
/// Safe cache/memory/registry tools. Never kills processes, never force-unlocks
/// in-use files, never touches drivers, BIOS, or Armoury repair state.
/// General cache cleaning still skips shader caches; shader cleanup is a
/// separate, allow-listed LocalAppData pass.
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

    private static readonly string[] ProtectedRegistryNames =
    {
        "Microsoft", "Windows", "Visual C++", "DirectX", "Armoury", "ASUS",
        "NVIDIA", "AMD", "Intel", "Realtek", "Visual Studio", ".NET",
        "奥创", "Windows Game Runtime"
    };

    private const int ProcessQueryLimitedInformation = 0x1000;
    private const int ProcessSetQuota = 0x0100;
    private const uint SherbNoConfirmation = 0x00000001;
    private const uint SherbNoProgressUi = 0x00000002;
    private const uint SherbNoSound = 0x00000004;
    private StreamWriter? _registryBackup;

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

    public Task<CacheScanResult> ScanShaderCacheAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => ToScan(CollectShaderBuckets(delete: false, cancellationToken)), cancellationToken);

    public Task<CacheCleanResult> CleanShaderCacheAsync(CancellationToken cancellationToken = default)
        => Task.Run(() =>
        {
            var buckets = CollectShaderBuckets(delete: true, cancellationToken);
            return new CacheCleanResult
            {
                BytesFreed = buckets.Sum(b => b.Bytes),
                FilesRemoved = buckets.Sum(b => b.Files),
                FilesSkipped = buckets.Sum(b => b.Skipped),
                RecycleBinEmptied = false,
                DnsFlushed = false,
                Buckets = buckets
            };
        }, cancellationToken);

    public Task<CacheScanResult> ScanRegistryAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => ToScan(CollectRegistryBuckets(delete: false, cancellationToken)), cancellationToken);

    public Task<RegistryCleanResult> CleanRegistryAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => CleanRegistry(cancellationToken), cancellationToken);

    public Task<string> RestoreLatestRegistryBackupAsync(CancellationToken cancellationToken = default)
        => Task.Run(() => RestoreLatestRegistryBackup(cancellationToken), cancellationToken);

    internal static Func<string> BackupDirectoryResolver { get; set; } = RegistryBackupDirectory;
    internal static Func<string>? BackupFileNameResolver { get; set; }
    internal static bool ForceBackupAppendFailure { get; set; }
    internal string? ShaderLocalAppDataOverride { get; set; }

    internal static void ResetTestHooks()
    {
        BackupDirectoryResolver = RegistryBackupDirectory;
        BackupFileNameResolver = null;
        ForceBackupAppendFailure = false;
    }

    public static string RegistryBackupDirectory()
        => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsGameRuntimeASUSSelfHealing",
            "RegistryBackups");

    public static string? LatestRegistryBackupPath()
    {
        var dir = BackupDirectoryResolver();
        if (!Directory.Exists(dir)) return null;
        return Directory.GetFiles(dir, "WGR_RegistryBackup_*.reg")
            .OrderByDescending(p => p, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
    }

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
        return ToScan(buckets);
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

    private static CacheScanResult ToScan(List<CacheBucket> buckets) => new()
    {
        Buckets = buckets,
        TotalBytes = buckets.Sum(b => b.Bytes),
        TotalFiles = buckets.Sum(b => b.Files)
    };

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

    private List<CacheBucket> CollectShaderBuckets(bool delete, CancellationToken cancellationToken)
    {
        var local = ShaderLocalAppDataOverride
            ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var targets = new (string name, string path)[]
        {
            ("DirectX 着色器缓存", Path.Combine(local, "D3DSCache")),
            ("NVIDIA 图形缓存", Path.Combine(local, "NVIDIA", "DXCache")),
            ("NVIDIA OpenGL 缓存", Path.Combine(local, "NVIDIA", "GLCache")),
            ("NVIDIA 驱动缓存", Path.Combine(local, "NVIDIA Corporation", "NV_Cache")),
            ("AMD 图形缓存", Path.Combine(local, "AMD", "DxCache")),
            ("AMD OpenGL 缓存", Path.Combine(local, "AMD", "GLCache")),
            ("Intel 着色器缓存", Path.Combine(local, "Intel", "ShaderCache")),
        };
        var list = new List<CacheBucket>();
        foreach (var (name, path) in targets)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsAllowedShaderPath(path, local))
            {
                list.Add(new CacheBucket { Name = name, Note = "当前没有或已跳过" });
                continue;
            }
            list.Add(Walk(name, path, delete, cancellationToken, optional: true, enforceForbidden: false, skipRecent: false));
        }
        return list;
    }

    private List<CacheBucket> CollectRegistryBuckets(bool delete, CancellationToken cancellationToken)
    {
        return
        [
            SweepUninstallLeftovers(delete, cancellationToken),
            SweepAppPaths(delete, cancellationToken),
            SweepInvalidRunValues(delete, cancellationToken),
            SweepMuiCache(delete, cancellationToken)
        ];
    }

    private RegistryCleanResult CleanRegistry(CancellationToken cancellationToken)
    {
        var dir = BackupDirectoryResolver();
        try
        {
            Directory.CreateDirectory(dir);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("无法创建注册表备份目录，已取消删除。", ex);
        }

        var backupName = BackupFileNameResolver?.Invoke()
            ?? $"WGR_RegistryBackup_{DateTime.Now:yyyyMMdd_HHmmss}.reg";
        var backupPath = Path.Combine(dir, backupName);
        StreamWriter writer;
        try
        {
            var fs = new FileStream(backupPath, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
            writer = new StreamWriter(fs, Encoding.Unicode);
            writer.WriteLine("Windows Registry Editor Version 5.00");
            writer.Flush();
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("无法写入注册表备份，已取消删除。", ex);
        }

        _registryBackup = writer;
        List<CacheBucket> buckets;
        try
        {
            buckets = CollectRegistryBuckets(delete: true, cancellationToken);
        }
        finally
        {
            try { writer.Flush(); } catch { }
            writer.Dispose();
            _registryBackup = null;
        }

        var removed = buckets.Sum(b => b.Files);
        if (removed == 0)
        {
            try { File.Delete(backupPath); } catch { }
            backupPath = "";
        }

        return new RegistryCleanResult
        {
            ItemsRemoved = removed,
            ItemsSkipped = buckets.Sum(b => b.Skipped),
            BackupPath = string.IsNullOrWhiteSpace(backupPath) ? null : backupPath,
            Buckets = buckets
        };
    }

    private static string RestoreLatestRegistryBackup(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var latest = LatestRegistryBackupPath()
            ?? throw new InvalidOperationException("还没有注册表备份可以还原。");
        using var process = Process.Start(new ProcessStartInfo
        {
            FileName = "reg.exe",
            Arguments = "import \"" + latest + "\"",
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        }) ?? throw new InvalidOperationException("无法启动 reg.exe。");
        process.WaitForExit(20000);
        if (process.ExitCode != 0)
            throw new InvalidOperationException("还原失败。系统项可能需要管理员权限。");
        return "已从备份还原：" + latest;
    }

    internal static bool TryAppendRegistryKey(TextWriter writer, string keyName, IEnumerable<(string Name, object? Value, RegistryValueKind Kind)> values)
    {
        if (writer is null || string.IsNullOrWhiteSpace(keyName)) return false;
        try
        {
            writer.WriteLine();
            writer.WriteLine("[" + keyName + "]");
            foreach (var (name, value, kind) in values)
            {
                writer.WriteLine(FormatRegLine(name, value, kind));
            }
            writer.Flush();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private bool WriteRegistryBackup(RegistryKey key)
    {
        if (ForceBackupAppendFailure) return false;
        if (_registryBackup is null || key is null) return false;
        var values = new List<(string Name, object? Value, RegistryValueKind Kind)>();
        foreach (var name in key.GetValueNames())
        {
            try { values.Add((name, key.GetValue(name), key.GetValueKind(name))); }
            catch { }
        }
        return TryAppendRegistryKey(_registryBackup, key.Name, values);
    }

    private bool WriteRegistryValueBackup(string keyName, string valueName, object? value, RegistryValueKind kind)
    {
        if (ForceBackupAppendFailure) return false;
        if (_registryBackup is null) return false;
        return TryAppendRegistryKey(_registryBackup, keyName, new[] { (valueName, value, kind) });
    }

    private static string FormatRegLine(string name, object? value, RegistryValueKind kind)
    {
        var key = string.IsNullOrEmpty(name) ? "@" : "\"" + EscapeReg(name) + "\"";
        if (kind == RegistryValueKind.DWord)
            return key + "=dword:" + Convert.ToUInt32(value ?? 0).ToString("x8");
        if (kind == RegistryValueKind.String || kind == RegistryValueKind.ExpandString)
            return key + "=\"" + EscapeReg(Convert.ToString(value) ?? "") + "\"";
        return key + "=\"" + EscapeReg(Convert.ToString(value) ?? "") + "\"";
    }

    private static string EscapeReg(string text) => text.Replace("\\", "\\\\").Replace("\"", "\\\"");

    private CacheBucket Walk(string name, string root, bool delete, CancellationToken cancellationToken, bool optional = false, Func<string, bool>? filePredicate = null, bool enforceForbidden = true, bool skipRecent = true)
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
            if (enforceForbidden && IsForbidden(path)) { skipped++; continue; }
            try
            {
                var info = new FileInfo(path);
                if ((info.Attributes & FileAttributes.System) != 0) { skipped++; continue; }
                if (skipRecent && info.LastWriteTimeUtc > cutoff) { skipped++; continue; }
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

    internal static bool IsAllowedShaderPath(string path, string? localAppData = null)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        try
        {
            var localRoot = string.IsNullOrWhiteSpace(localAppData)
                ? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
                : localAppData;
            var local = Path.GetFullPath(localRoot).TrimEnd('\\') + "\\";
            var full = Path.GetFullPath(path).TrimEnd('\\') + "\\";
            if (!full.StartsWith(local, StringComparison.OrdinalIgnoreCase)) return false;
            var n = full.ToLowerInvariant();
            return n.Contains("\\d3dscache\\") ||
                   n.Contains("\\nvidia\\dxcache\\") ||
                   n.Contains("\\nvidia\\glcache\\") ||
                   n.Contains("\\nvidia corporation\\nv_cache\\") ||
                   n.Contains("\\amd\\dxcache\\") ||
                   n.Contains("\\amd\\glcache\\") ||
                   n.Contains("\\intel\\shadercache\\");
        }
        catch { return false; }
    }

    private static bool PathsEqual(string a, string b)
    {
        try { return string.Equals(Path.GetFullPath(a).TrimEnd('\\'), Path.GetFullPath(b).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }

    internal static bool IsProtectedName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return true;
        foreach (var token in ProtectedRegistryNames)
        {
            if (name.Contains(token, StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    private static string? FirstExistingCheckPath(string? command)
    {
        if (string.IsNullOrWhiteSpace(command)) return null;
        var expanded = Environment.ExpandEnvironmentVariables(command.Trim());
        if (expanded.StartsWith('"'))
        {
            var end = expanded.IndexOf('"', 1);
            if (end > 1) return expanded[1..end];
        }
        var exe = expanded.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        if (exe >= 0) return expanded[..(exe + 4)].Trim().Trim('"');
        var space = expanded.IndexOf(' ');
        return (space > 0 ? expanded[..space] : expanded).Trim().Trim('"');
    }

    internal static bool LooksMissing(string? command)
    {
        var path = FirstExistingCheckPath(command);
        if (string.IsNullOrWhiteSpace(path)) return false;
        if (path.Contains("msiexec", StringComparison.OrdinalIgnoreCase)) return false;
        if (path.Contains("rundll32", StringComparison.OrdinalIgnoreCase)) return false;
        try
        {
            if (path.EndsWith('\\')) return !Directory.Exists(path);
            return !File.Exists(path) && !Directory.Exists(path);
        }
        catch { return false; }
    }

    private CacheBucket SweepUninstallLeftovers(bool delete, CancellationToken cancellationToken)
    {
        var files = 0;
        var skipped = 0;
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(hive, view);
                using var uninstall = baseKey.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall", writable: delete);
                if (uninstall is null) continue;
                foreach (var name in uninstall.GetSubKeyNames())
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (files + skipped > 4000) break;
                    try
                    {
                        using var sub = uninstall.OpenSubKey(name, writable: false);
                        if (sub is null) { skipped++; continue; }
                        var display = sub.GetValue("DisplayName") as string;
                        if (IsProtectedName(display)) { skipped++; continue; }
                        var uninstallString = sub.GetValue("UninstallString") as string;
                        if (string.IsNullOrWhiteSpace(uninstallString) || !LooksMissing(uninstallString)) { skipped++; continue; }
                        if (delete)
                        {
                            if (!WriteRegistryBackup(sub)) { skipped++; continue; }
                            uninstall.DeleteSubKeyTree(name, throwOnMissingSubKey: false);
                        }
                        files++;
                    }
                    catch { skipped++; }
                }
            }
            catch { skipped++; }
        }
        return new CacheBucket { Name = "卸载残留", Files = files, Skipped = skipped, Note = "只删已经卸掉、路径不存在的项" };
    }

    private CacheBucket SweepAppPaths(bool delete, CancellationToken cancellationToken)
    {
        var files = 0;
        var skipped = 0;
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(hive, view);
                using var appPaths = baseKey.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths", writable: delete);
                if (appPaths is null) continue;
                foreach (var name in appPaths.GetSubKeyNames())
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (IsProtectedName(name)) { skipped++; continue; }
                    try
                    {
                        using var sub = appPaths.OpenSubKey(name, writable: false);
                        if (sub is null) { skipped++; continue; }
                        var target = sub.GetValue(null) as string ?? sub.GetValue("Path") as string;
                        if (!LooksMissing(target)) { skipped++; continue; }
                        if (delete)
                        {
                            if (!WriteRegistryBackup(sub)) { skipped++; continue; }
                            appPaths.DeleteSubKeyTree(name, throwOnMissingSubKey: false);
                        }
                        files++;
                    }
                    catch { skipped++; }
                }
            }
            catch { skipped++; }
        }
        return new CacheBucket { Name = "无效程序路径", Files = files, Skipped = skipped };
    }

    private CacheBucket SweepInvalidRunValues(bool delete, CancellationToken cancellationToken)
    {
        var files = 0;
        var skipped = 0;
        var runPaths = new[]
        {
            @"Software\Microsoft\Windows\CurrentVersion\Run",
            @"Software\Microsoft\Windows\CurrentVersion\RunOnce"
        };
        foreach (var hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        foreach (var path in runPaths)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var baseKey = RegistryKey.OpenBaseKey(hive, view);
                using var run = baseKey.OpenSubKey(path, writable: delete);
                if (run is null) continue;
                foreach (var name in run.GetValueNames())
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (IsProtectedName(name)) { skipped++; continue; }
                    try
                    {
                        var value = run.GetValue(name) as string;
                        if (!LooksMissing(value)) { skipped++; continue; }
                        if (delete)
                        {
                            if (!WriteRegistryValueBackup(run.Name, name, value, run.GetValueKind(name))) { skipped++; continue; }
                            run.DeleteValue(name, throwOnMissingValue: false);
                        }
                        files++;
                    }
                    catch { skipped++; }
                }
            }
            catch { skipped++; }
        }
        return new CacheBucket { Name = "无效启动项", Files = files, Skipped = skipped };
    }

    private CacheBucket SweepMuiCache(bool delete, CancellationToken cancellationToken)
    {
        var files = 0;
        var skipped = 0;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache", writable: delete);
            if (key is null)
                return new CacheBucket { Name = "无效文件名缓存", Note = "当前没有或无权访问" };
            foreach (var name in key.GetValueNames())
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (files + skipped > 8000) break;
                var path = name;
                var cut = path.LastIndexOf('.');
                if (cut > 2) path = path[..cut];
                if (!path.Contains('\\') || !LooksMissing(path)) { skipped++; continue; }
                try
                {
                    if (delete)
                    {
                        if (!WriteRegistryValueBackup(key.Name, name, key.GetValue(name), key.GetValueKind(name))) { skipped++; continue; }
                        key.DeleteValue(name, throwOnMissingValue: false);
                    }
                    files++;
                }
                catch { skipped++; }
            }
        }
        catch { skipped++; }
        return new CacheBucket { Name = "无效文件名缓存", Files = files, Skipped = skipped };
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
