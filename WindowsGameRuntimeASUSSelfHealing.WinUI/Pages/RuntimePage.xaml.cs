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
            if (cached.Count > 0) ApplyLocalVerdict("已有检测结果");
            else await RefreshLocalAsync(false);
        };
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshLocalAsync(true);

    private async Task RefreshLocalAsync(bool force)
    {
        RefreshButton.IsEnabled = false;
        RuntimeInfo.Title = "正在检测";
        RuntimeInfo.Message = "正在查看本机 C++ 运行库和 DirectX。";
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
            ApplyLocalVerdict("检测完成");
        }
        catch (Exception ex)
        {
            RuntimeInfo.Title = "检测失败";
            RuntimeInfo.Message = CustomerCopy.Plain(ex.Message);
            RuntimeInfo.Severity = InfoBarSeverity.Error;
            App.Services.SessionLog.Bug("Runtime.Local", ex);
        }
        finally { RefreshButton.IsEnabled = true; }
    }

    private void ApplyLocalVerdict(string title)
    {
        var broken = _rows.Any(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");
        var warn = _rows.Any(x => x.Status is "WARN" or "UPDATE");
        RuntimeInfo.Title = title;
        if (broken)
        {
            RuntimeInfo.Message = "有运行库不完整。本工具不会自动安装，请按每条结果自行处理。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else if (warn)
        {
            RuntimeInfo.Message = "可以玩游戏，但有项目版本偏低，建议更新。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else
        {
            RuntimeInfo.Message = "结论：不必修复。C++ 运行库和 DirectX 都可用。";
            RuntimeInfo.Severity = InfoBarSeverity.Success;
        }
    }
}
