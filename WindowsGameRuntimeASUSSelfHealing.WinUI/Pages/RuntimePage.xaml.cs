using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class RuntimePage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private readonly ObservableCollection<ComponentItem> _rows = new();
    private bool _loaded;

    public RuntimePage()
    {
        InitializeComponent();
        RuntimeRows.ItemsSource = _rows;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            var cached = await App.Services.StateStore.ReadComponentStatesAsync("RUNTIME");
            foreach (var row in cached) _rows.Add(row);
            if (cached.Count > 0) ApplyLocalVerdict("已加载本机检测缓存");
            else await RefreshLocalAsync(false);
        };
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshLocalAsync(true);

    private async Task RefreshLocalAsync(bool force)
    {
        RefreshButton.IsEnabled = false;
        RuntimeInfo.Title = "本机检测中";
        RuntimeInfo.Message = "只读本机 VC++ / DirectX 文件与注册表，不下载 Microsoft 官方安装器。";
        RuntimeInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            using var r = await _backend.RunAsync("DASHBOARD", force: force, timeout: TimeSpan.FromMinutes(2));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            _rows.Clear();
            foreach (var e in r.Payload.Array("Components"))
            {
                var row = PageHelpers.ToComponent(e);
                if (row.Group.Equals("RUNTIME", StringComparison.OrdinalIgnoreCase))
                    _rows.Add(row);
            }
            await App.Services.StateStore.UpsertComponentStatesAsync(_rows);
            ApplyLocalVerdict("本机检测完成");
        }
        catch (Exception ex)
        {
            RuntimeInfo.Title = "本机检测失败";
            RuntimeInfo.Message = ex.Message;
            RuntimeInfo.Severity = InfoBarSeverity.Error;
            App.Services.SessionLog.Bug("Runtime.Local", ex);
        }
        finally { RefreshButton.IsEnabled = true; }
    }

    private void ApplyLocalVerdict(string title)
    {
        var broken = _rows.Any(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");
        RuntimeInfo.Title = title;
        if (broken)
        {
            RuntimeInfo.Message = "本机运行库文件异常。本工具不再下载 Microsoft 官方安装器，请自行安装 Visual C++ Redistributable 或 DirectX End-User Runtime。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else
        {
            RuntimeInfo.Message = "本机 VC++ / DirectX 可用。已停用官方包对比和自动修复，最终验收不再因此标 WARN。";
            RuntimeInfo.Severity = InfoBarSeverity.Success;
        }
    }
}
