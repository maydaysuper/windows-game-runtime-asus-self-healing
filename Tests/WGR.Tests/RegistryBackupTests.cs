using System.IO;
using System.Text;
using Microsoft.Win32;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;
using Xunit;

namespace WGR.Tests;

public sealed class RegistryBackupTests
{
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
    public async Task CleanRegistry_throws_and_does_not_delete_when_backup_dir_is_a_file()
    {
        var blocker = Path.GetTempFileName();
        var previous = SystemMaintenanceService.BackupDirectoryResolver;
        try
        {
            SystemMaintenanceService.BackupDirectoryResolver = () => blocker;
            var svc = new SystemMaintenanceService();
            var ex = await Assert.ThrowsAsync<InvalidOperationException>(() => svc.CleanRegistryAsync());
            Assert.Contains("备份", ex.Message);
            Assert.True(File.Exists(blocker));
        }
        finally
        {
            SystemMaintenanceService.BackupDirectoryResolver = previous;
            try { File.Delete(blocker); } catch { }
        }
    }

    private sealed class ThrowingWriter : StringWriter
    {
        public override void WriteLine() => throw new IOException("disk full");
        public override void WriteLine(string? value) => throw new IOException("disk full");
    }
}
