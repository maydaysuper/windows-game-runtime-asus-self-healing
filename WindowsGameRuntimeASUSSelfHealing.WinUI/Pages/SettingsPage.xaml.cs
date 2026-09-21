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
        if (!await PageHelpers.ConfirmAsync(this, "清理系统缓存", "会删除可安全删除的临时文件，并清空回收站。正在使用的文件会跳过。不会结束正在运行的程序，也不会动奥创修复和显卡着色器缓存。", "立即清理"))
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
        await Task.WhenAll(ScanCacheAsync(), RefreshMemoryAsync(), RefreshAppCacheAsync());
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
