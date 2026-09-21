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

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void ClearCacheButton_Click(object sender, RoutedEventArgs e)
    {
        if (!await PageHelpers.ConfirmAsync(this, "清理易失缓存", "只会清理 Event Log 缓存、增量游标和组件状态快照。修复事务与 Incident 历史会保留。", "清理")) return;
        try
        {
            await App.Services.StateStore.ClearVolatileCacheAsync();
            await RefreshAsync();
        }
        catch (Exception ex) { await PageHelpers.ShowAsync(this, "缓存清理失败", ex.Message); }
    }

    private async Task RefreshAsync()
    {
        RefreshButton.IsEnabled = false;
        try
        {
            var status = await App.Services.StateStore.GetStatusAsync();
            DbPathText.Text = status.DatabasePath;
            DbModeText.Text = $"schema={status.SchemaVersion} · journal={status.JournalMode}";
            DbCountText.Text = $"crash={status.CrashEventCount} · components={status.ComponentCount} · transactions={status.TransactionCount} · incidents={status.IncidentCount} · dumps={status.DumpAnalysisCount}";
            DbSizeText.Text = status.DatabaseBytes < 1024 * 1024
                ? $"{status.DatabaseBytes / 1024.0:N1} KB（含 WAL/SHM）"
                : $"{status.DatabaseBytes / 1024.0 / 1024.0:N1} MB（含 WAL/SHM）";
            EventSyncText.Text = status.LastEventSyncUtc.HasValue
                ? $"最近成功：{status.LastEventSyncUtc.Value.ToLocalTime():yyyy-MM-dd HH:mm:ss}" + (string.IsNullOrWhiteSpace(status.LastEventSyncError) ? "" : $" · 最近错误：{status.LastEventSyncError}")
                : "尚未完成首次事件增量同步";
            WorkflowText.Text = status.WorkflowState;

            var perf = App.Services.Performance.LastDurationsMs.OrderBy(x => x.Key).ToArray();
            PerfText.Text = perf.Length == 0
                ? "本次会话尚无性能采样。"
                : string.Join("\n", perf.Select(x => $"{x.Key} = {x.Value} ms"));
            Info.Title = "SQLite 状态正常";
            Info.Message = "事件、组件、Incident 与 Transaction 已进入本地增量状态层。";
            Info.Severity = InfoBarSeverity.Success;
        }
        catch (Exception ex)
        {
            Info.Title = "状态数据库不可用";
            Info.Message = ex.Message;
            Info.Severity = InfoBarSeverity.Error;
        }
        finally { RefreshButton.IsEnabled = true; }
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
