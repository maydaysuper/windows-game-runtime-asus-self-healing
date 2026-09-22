using System.Windows;
using System.Windows.Controls;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class SettingsPage : Page
{
    private bool _loaded;

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            await RefreshAsync();
        };
    }

    private async void ScanCache_Click(object sender, RoutedEventArgs e) => await ScanCacheAsync();

    private async void CleanCache_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理系统缓存", "会删除可安全删除的临时文件，并清空回收站。正在使用的文件会跳过。不会结束正在运行的程序。着色器缓存请用下面单独的卡片。", "立即清理"))
            return;
        CleanCacheButton.IsEnabled = false;
        ScanCacheButton.IsEnabled = false;
        try
        {
            var result = await App.Services.Maintenance.CleanCacheAsync();
            CacheText.Text = result.ResultLine + "\n" + string.Join("\n", result.Buckets.Select(b => b.Line));
            Info.Title = "缓存已清理";
            Info.Message = result.ResultLine;
            Info.Severity = InfoBarSeverity.Success;
            App.Services.SessionLog.Note("CacheClean", result.ResultLine);
        }
        catch (Exception ex)
        {
            Info.Title = "缓存清理失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally
        {
            CleanCacheButton.IsEnabled = true;
            ScanCacheButton.IsEnabled = true;
        }
    }

    private async void ScanShader_Click(object sender, RoutedEventArgs e) => await ScanShaderAsync();

    private async void CleanShader_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理显卡着色器缓存", "会清理 DirectX / NVIDIA / AMD / Intel 的着色器缓存。正在被游戏占用的文件会跳过。下次开游戏可能会重新编译，开头可能卡一下。不会结束正在运行的程序，也不会卸驱动。", "立即清理"))
            return;
        ScanShaderButton.IsEnabled = false;
        CleanShaderButton.IsEnabled = false;
        try
        {
            var result = await App.Services.Maintenance.CleanShaderCacheAsync();
            ShaderText.Text = result.ResultLine + "\n" + string.Join("\n", result.Buckets.Select(b => b.Line));
            Info.Title = "着色器缓存已清理";
            Info.Message = result.ResultLine;
            Info.Severity = InfoBarSeverity.Success;
            App.Services.SessionLog.Note("ShaderClean", result.ResultLine);
        }
        catch (Exception ex)
        {
            Info.Title = "着色器缓存清理失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally
        {
            ScanShaderButton.IsEnabled = true;
            CleanShaderButton.IsEnabled = true;
        }
    }

    private async void ScanRegistry_Click(object sender, RoutedEventArgs e) => await ScanRegistryAsync();

    private async void CleanRegistry_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理注册表残留", "只删除指向已经不存在文件的残留项。不会改驱动、奥创中心、微软运行库和系统服务。无权修改的系统项会自动跳过。", "立即清理"))
            return;
        ScanRegistryButton.IsEnabled = false;
        CleanRegistryButton.IsEnabled = false;
        try
        {
            var result = await App.Services.Maintenance.CleanRegistryAsync();
            RegistryText.Text = result.ResultLine + "\n" + string.Join("\n", result.Buckets.Select(b => b.Line));
            Info.Title = "注册表已清理";
            Info.Message = result.ResultLine;
            Info.Severity = InfoBarSeverity.Success;
            App.Services.SessionLog.Note("RegistryClean", result.ResultLine);
        }
        catch (Exception ex)
        {
            Info.Title = "注册表清理失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally
        {
            ScanRegistryButton.IsEnabled = true;
            CleanRegistryButton.IsEnabled = true;
        }
    }

    private async void CleanMemory_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理内存", "会把闲置内存还给系统。正在运行的游戏和软件都不会被关闭。", "立即清理"))
            return;
        CleanMemoryButton.IsEnabled = false;
        try
        {
            var result = await App.Services.Maintenance.CleanMemoryAsync();
            MemoryText.Text = result.After.Summary + "\n" + result.ResultLine;
            Info.Title = "内存已整理";
            Info.Message = result.ResultLine;
            Info.Severity = InfoBarSeverity.Success;
            App.Services.SessionLog.Note("MemoryClean", result.ResultLine);
        }
        catch (Exception ex)
        {
            Info.Title = "内存清理失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { CleanMemoryButton.IsEnabled = true; }
    }

    private async void ClearCacheButton_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理本软件检测缓存", "只会清理本软件的事件缓存、增量游标和组件状态快照。修复事务与历史会保留。这不是系统缓存清理。", "清理"))
            return;
        try
        {
            await App.Services.StateStore.ClearVolatileCacheAsync();
            await RefreshAppCacheAsync();
            Info.Title = "本软件缓存已清理";
            Info.Message = "事件缓存已清空。修复记录还在。";
            Info.Severity = InfoBarSeverity.Success;
        }
        catch (Exception ex) { await PageHelpers.ShowAsync(this, "本软件缓存清理失败", ex.Message); }
    }

    private async Task RefreshAsync()
    {
        await Task.WhenAll(ScanCacheAsync(), ScanShaderAsync(), ScanRegistryAsync(), RefreshMemoryAsync(), RefreshAppCacheAsync());
    }

    private async Task ScanCacheAsync()
    {
        ScanCacheButton.IsEnabled = false;
        CleanCacheButton.IsEnabled = false;
        try
        {
            var scan = await App.Services.Maintenance.ScanCacheAsync();
            CacheText.Text = scan.Summary + "\n" + string.Join("\n", scan.Buckets.Select(b => b.Line));
            Info.Title = "可以清理";
            Info.Message = scan.Summary;
            Info.Severity = InfoBarSeverity.Informational;
        }
        catch (Exception ex)
        {
            CacheText.Text = "扫描失败：" + ex.Message;
            Info.Title = "扫描失败";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally
        {
            ScanCacheButton.IsEnabled = true;
            CleanCacheButton.IsEnabled = true;
        }
    }

    private async Task ScanShaderAsync()
    {
        ScanShaderButton.IsEnabled = false;
        CleanShaderButton.IsEnabled = false;
        try
        {
            var scan = await App.Services.Maintenance.ScanShaderCacheAsync();
            ShaderText.Text = scan.Summary + "\n" + string.Join("\n", scan.Buckets.Select(b => b.Line));
        }
        catch (Exception ex)
        {
            ShaderText.Text = "扫描失败：" + ex.Message;
        }
        finally
        {
            ScanShaderButton.IsEnabled = true;
            CleanShaderButton.IsEnabled = true;
        }
    }

    private async Task ScanRegistryAsync()
    {
        ScanRegistryButton.IsEnabled = false;
        CleanRegistryButton.IsEnabled = false;
        try
        {
            var scan = await App.Services.Maintenance.ScanRegistryAsync();
            RegistryText.Text = (scan.TotalFiles == 0
                ? "没有发现可安全删除的注册表残留。"
                : $"大约 {scan.TotalFiles} 项无效残留。受保护和无权修改的会跳过。")
                + "\n" + string.Join("\n", scan.Buckets.Select(b => b.Line));
        }
        catch (Exception ex)
        {
            RegistryText.Text = "扫描失败：" + ex.Message;
        }
        finally
        {
            ScanRegistryButton.IsEnabled = true;
            CleanRegistryButton.IsEnabled = true;
        }
    }

    private Task RefreshMemoryAsync()
    {
        try
        {
            var snap = App.Services.Maintenance.ReadMemory();
            MemoryText.Text = snap.Summary;
        }
        catch (Exception ex)
        {
            MemoryText.Text = "无法读取内存：" + ex.Message;
        }
        return Task.CompletedTask;
    }

    private async Task RefreshAppCacheAsync()
    {
        try
        {
            var status = await App.Services.StateStore.GetStatusAsync();
            var size = status.DatabaseBytes < 1024 * 1024
                ? $"{status.DatabaseBytes / 1024.0:N1} KB"
                : $"{status.DatabaseBytes / 1024.0 / 1024.0:N1} MB";
            AppCacheText.Text = $"本软件数据库 {size} · 崩溃 {status.CrashEventCount} · 修复记录 {status.TransactionCount} · 事件 {status.IncidentCount}";
        }
        catch (Exception ex)
        {
            AppCacheText.Text = "无法读取本软件缓存：" + ex.Message;
        }
    }

    private void OpenDeepTest_Click(object sender, RoutedEventArgs e)
        => NavigationService?.Navigate(new DeepTestPage());

    private void OpenIdentity_Click(object sender, RoutedEventArgs e)
        => NavigationService?.Navigate(new IdentityPage());

    private void OpenArchitecture_Click(object sender, RoutedEventArgs e)
        => NavigationService?.Navigate(new ArchitecturePage());

    private void BackToReports_Click(object sender, RoutedEventArgs e)
        => NavigationService?.Navigate(new ReportsPage());
}
