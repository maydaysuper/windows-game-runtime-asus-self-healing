using System.IO;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;
using Xunit;

namespace WGR.Tests;

public sealed class ShaderCacheTests
{
    [Fact]
    public void IsAllowedShaderPath_accepts_local_d3d_cache_and_rejects_system32()
    {
        var local = Path.Combine(Path.GetTempPath(), "wgr-shader-" + Guid.NewGuid().ToString("N"));
        var d3d = Path.Combine(local, "D3DSCache");
        Directory.CreateDirectory(d3d);
        try
        {
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(d3d, local));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath(@"C:\Windows\System32\D3DSCache", local));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "RandomCache"), local));
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanShaderCache_is_idempotent()
    {
        var local = Path.Combine(Path.GetTempPath(), "wgr-shader-" + Guid.NewGuid().ToString("N"));
        var d3d = Path.Combine(local, "D3DSCache");
        Directory.CreateDirectory(d3d);
        File.WriteAllText(Path.Combine(d3d, "stale.bin"), new string('x', 4096));
        var svc = new SystemMaintenanceService { ShaderLocalAppDataOverride = local };
        try
        {
            var first = await svc.CleanShaderCacheAsync();
            Assert.True(first.FilesRemoved >= 1);
            Assert.False(File.Exists(Path.Combine(d3d, "stale.bin")));

            var second = await svc.CleanShaderCacheAsync();
            Assert.Equal(0, second.FilesRemoved);
            Assert.True(Directory.Exists(d3d));
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }
}
