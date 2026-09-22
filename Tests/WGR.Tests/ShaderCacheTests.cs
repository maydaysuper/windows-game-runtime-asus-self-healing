using System.IO;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;
using Xunit;

namespace WGR.Tests;

public sealed class ShaderCacheTests
{
    [Fact]
    public void IsAllowedShaderPath_accepts_local_vendor_caches_and_rejects_system32()
    {
        var local = Path.Combine(Path.GetTempPath(), "wgr-shader-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(local);
        try
        {
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "D3DSCache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "NVIDIA", "DXCache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "NVIDIA", "GLCache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "NVIDIA Corporation", "NV_Cache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "AMD", "DxCache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "AMD", "GLCache"), local));
            Assert.True(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "Intel", "ShaderCache"), local));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath(@"C:\Windows\System32\D3DSCache", local));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath(Path.Combine(local, "RandomCache"), local));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath("", local));
            var escaped = Path.GetFullPath(Path.Combine(local, "..", "Windows", "D3DSCache"));
            Assert.False(SystemMaintenanceService.IsAllowedShaderPath(escaped, local));
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanShaderCache_is_idempotent_across_three_runs()
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
            Assert.True(Directory.Exists(d3d));

            var second = await svc.CleanShaderCacheAsync();
            Assert.Equal(0, second.FilesRemoved);
            Assert.True(Directory.Exists(d3d));

            var third = await svc.CleanShaderCacheAsync();
            Assert.Equal(0, third.FilesRemoved);
            Assert.True(Directory.Exists(d3d));
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanShaderCache_missing_and_empty_dirs_do_not_throw()
    {
        var local = Path.Combine(Path.GetTempPath(), "wgr-shader-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(local);
        var svc = new SystemMaintenanceService { ShaderLocalAppDataOverride = local };
        try
        {
            var missing = await svc.CleanShaderCacheAsync();
            Assert.Equal(0, missing.FilesRemoved);

            Directory.CreateDirectory(Path.Combine(local, "D3DSCache"));
            var empty = await svc.CleanShaderCacheAsync();
            Assert.Equal(0, empty.FilesRemoved);
            Assert.True(Directory.Exists(Path.Combine(local, "D3DSCache")));
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }

    [Fact]
    public async Task CleanShaderCache_skips_in_use_file_without_throwing()
    {
        var local = Path.Combine(Path.GetTempPath(), "wgr-shader-" + Guid.NewGuid().ToString("N"));
        var d3d = Path.Combine(local, "D3DSCache");
        Directory.CreateDirectory(d3d);
        var locked = Path.Combine(d3d, "locked.bin");
        File.WriteAllText(locked, new string('y', 2048));
        var svc = new SystemMaintenanceService { ShaderLocalAppDataOverride = local };
        try
        {
            using (var hold = new FileStream(locked, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                var result = await svc.CleanShaderCacheAsync();
                Assert.True(result.FilesSkipped >= 1);
                Assert.True(File.Exists(locked));
            }
        }
        finally
        {
            try { Directory.Delete(local, true); } catch { }
        }
    }
}
