using System.IO;
using System.Text;
using Microsoft.Win32;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;
using Xunit;

namespace WGR.Tests;

public sealed class RegistryBackupTests : IDisposable
{
    public RegistryBackupTests() => SystemMaintenanceService.ResetTestHooks();
    public void Dispose() => SystemMaintenanceService.ResetTestHooks();

    [Fact]
    public void TryAppendRegistryKey_writes_unicode_reg_header_body()
    {
        using var writer = new StringWriter();
        var ok = SystemMaintenanceService.TryAppendRegistryKey(
            writer,
            @"HKEY_CURRENT_USER\Software\WgrTest",
            new[] { ("DisplayName", (object?)"gone", RegistryValueKind.String) });
        Assert.True(ok);
        var text = writer.ToString();
        Assert.Contains("[HKEY_CURRENT_USER\\Software\\WgrTest]", text);
        Assert.Contains("DisplayName", text);
        Assert.Contains("gone", text);
    }

    [Fact]
    public void TryAppendRegistryKey_returns_false_when_writer_throws()
    {
        using var writer = new ThrowingWriter();
        var ok = SystemMaintenanceService.TryAppendRegistryKey(
            writer,
            @"HKEY_CURRENT_USER\Software\WgrTest",
            new[] { ("x", (object?)"y", RegistryValueKind.String) });
        Assert.False(ok);
    }

    [Fact]
    public void TryAppendRegistryKey_rejects_null_or_empty_key()
    {
        using var writer = new StringWriter();
        Assert.False(SystemMaintenanceService.TryAppendRegistryKey(writer, "", new[] { ("x", (object?)"y", RegistryValueKind.String) }));
        Assert.False(SystemMaintenanceService.TryAppendRegistryKey(null!, @"HKCU\x", new[] { ("x", (object?)"y", RegistryValueKind.String) }));
    }

    [Fact]
    public async Task CleanRegistry_throws_and_does_not_delete_when_backup_dir_is_a_file()
    {
        var blocker = Path.GetTempFileName();
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => blocker;
            var leftover = CreateUninstallLeftover("Wgr Leftover DirBlock", missingUninstall: true);
            try
            {
                var svc = new SystemMaintenanceService();
                var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => svc.CleanRegistryAsync());
                Assert.Contains("备份", ex.Message);
                Assert.True(File.Exists(blocker));
                Assert.NotNull(Registry.CurrentUser.OpenSubKey(leftover));
            }
            finally { DeleteUninstallLeftover(leftover); }
        }
        finally
        {
            try { File.Delete(blocker); } catch { }
        }
    }

    [Fact]
    public async Task CleanRegistry_throws_and_keeps_key_when_backup_file_already_exists()
    {
        var dir = Path.Combine(Path.GetTempPath(), "wgr-reg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var blocked = Path.Combine(dir, "WGR_RegistryBackup_blocked.reg");
        File.WriteAllText(blocked, "occupied");
        var leftover = CreateUninstallLeftover("Wgr Leftover FileBlock", missingUninstall: true);
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => dir;
            SystemMaintenanceService.BackupFileNameResolver = () => "WGR_RegistryBackup_blocked.reg";
            var svc = new SystemMaintenanceService();
            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => svc.CleanRegistryAsync());
            Assert.Contains("无法写入注册表备份", ex.Message);
            Assert.NotNull(Registry.CurrentUser.OpenSubKey(leftover));
            Assert.Equal("occupied", File.ReadAllText(blocked));
        }
        finally
        {
            DeleteUninstallLeftover(leftover);
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanRegistry_skips_item_when_backup_append_fails()
    {
        var dir = Path.Combine(Path.GetTempPath(), "wgr-reg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var leftover = CreateUninstallLeftover("Wgr Leftover AppendFail", missingUninstall: true);
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => dir;
            SystemMaintenanceService.ForceBackupAppendFailure = true;
            var svc = new SystemMaintenanceService();
            var result = await svc.CleanRegistryAsync();
            Assert.Equal(0, result.ItemsRemoved);
            Assert.True(result.ItemsSkipped >= 1);
            Assert.NotNull(Registry.CurrentUser.OpenSubKey(leftover));
        }
        finally
        {
            DeleteUninstallLeftover(leftover);
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanRegistry_backs_up_then_deletes_missing_uninstall_leftover()
    {
        var dir = Path.Combine(Path.GetTempPath(), "wgr-reg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var leftover = CreateUninstallLeftover("Wgr Leftover HappyPath", missingUninstall: true);
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => dir;
            SystemMaintenanceService.BackupFileNameResolver = () => "WGR_RegistryBackup_happy.reg";
            var svc = new SystemMaintenanceService();
            var result = await svc.CleanRegistryAsync();
            Assert.True(result.ItemsRemoved >= 1);
            Assert.Null(Registry.CurrentUser.OpenSubKey(leftover));
            Assert.False(string.IsNullOrWhiteSpace(result.BackupPath));
            Assert.True(File.Exists(result.BackupPath));
            var backup = File.ReadAllText(result.BackupPath!, Encoding.Unicode);
            Assert.Contains("Windows Registry Editor Version 5.00", backup);
            Assert.Contains("Wgr Leftover HappyPath", backup);
        }
        finally
        {
            DeleteUninstallLeftover(leftover);
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanRegistry_does_not_delete_protected_microsoft_name()
    {
        var dir = Path.Combine(Path.GetTempPath(), "wgr-reg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var leftover = CreateUninstallLeftover("Microsoft Visual C++ 2099 Redistributable", missingUninstall: true);
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => dir;
            var svc = new SystemMaintenanceService();
            var result = await svc.CleanRegistryAsync();
            Assert.NotNull(Registry.CurrentUser.OpenSubKey(leftover));
            Assert.True(result.ItemsSkipped >= 1);
        }
        finally
        {
            DeleteUninstallLeftover(leftover);
            try { Directory.Delete(dir, true); } catch { }
        }
    }

    [Fact]
    public void LatestRegistryBackupPath_returns_newest_and_null_when_missing()
    {
        var dir = Path.Combine(Path.GetTempPath(), "wgr-reg-" + Guid.NewGuid().ToString("N"));
        SystemMaintenanceService.BackupDirectoryResolver = () => dir;
        Assert.Null(SystemMaintenanceService.LatestRegistryBackupPath());
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "WGR_RegistryBackup_aaa.reg"), "a");
        File.WriteAllText(Path.Combine(dir, "WGR_RegistryBackup_zzz.reg"), "z");
        var latest = SystemMaintenanceService.LatestRegistryBackupPath();
        Assert.EndsWith("WGR_RegistryBackup_zzz.reg", latest, StringComparison.OrdinalIgnoreCase);
        try { Directory.Delete(dir, true); } catch { }
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData("", true)]
    [InlineData("Microsoft Edge", true)]
    [InlineData("奥创中心", true)]
    [InlineData("Armoury Crate", true)]
    [InlineData("NVIDIA Graphics", true)]
    [InlineData("Wgr Leftover Unit Test", false)]
    public void IsProtectedName_covers_vendors_and_empty(string? name, bool expected)
        => Assert.Equal(expected, SystemMaintenanceService.IsProtectedName(name));

    [Fact]
    public void LooksMissing_ignores_msiexec_and_existing_files()
    {
        Assert.False(SystemMaintenanceService.LooksMissing(null));
        Assert.False(SystemMaintenanceService.LooksMissing(@"C:\Windows\System32\msiexec.exe /x {GUID}"));
        var existing = Path.GetTempFileName();
        try
        {
            Assert.False(SystemMaintenanceService.LooksMissing(existing));
            Assert.False(SystemMaintenanceService.LooksMissing("\"" + existing + "\" /uninstall"));
        }
        finally { try { File.Delete(existing); } catch { } }
        Assert.True(SystemMaintenanceService.LooksMissing(@"C:\WgrDoesNotExist\gone.exe"));
    }

    private static string CreateUninstallLeftover(string displayName, bool missingUninstall)
    {
        var id = "WgrUnitTest-" + Guid.NewGuid().ToString("N");
        var path = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + id;
        using var key = Registry.CurrentUser.CreateSubKey(path, true)
            ?? throw new InvalidOperationException("cannot create test uninstall key");
        key.SetValue("DisplayName", displayName, RegistryValueKind.String);
        key.SetValue(
            "UninstallString",
            missingUninstall
                ? @"C:\WgrDoesNotExist\" + id + @"\uninstall.exe"
                : Environment.GetFolderPath(Environment.SpecialFolder.System) + @"\notepad.exe",
            RegistryValueKind.String);
        return path;
    }

    private static void DeleteUninstallLeftover(string path)
    {
        try { Registry.CurrentUser.DeleteSubKeyTree(path, throwOnMissingSubKey: false); } catch { }
    }

    private sealed class ThrowingWriter : StringWriter
    {
        public override void WriteLine() => throw new IOException("disk full");
        public override void WriteLine(string? value) => throw new IOException("disk full");
    }
}
