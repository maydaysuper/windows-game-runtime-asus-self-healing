using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class RuntimePage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private readonly BrokerService _broker = App.Services.Broker;
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
        RepairButton.IsEnabled = false;
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
        finally
        {
            RefreshButton.IsEnabled = true;
            RepairButton.IsEnabled = true;
        }
    }

    private async void RepairButton_Click(object sender, RoutedEventArgs e)
    {
        RefreshButton.IsEnabled = false;
        RepairButton.IsEnabled = false;
        RuntimeInfo.Title = "正在判断能不能修";
        RuntimeInfo.Message = "先看本机 C++ 运行库和 DirectX，再决定要不要动手。";
        RuntimeInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            using var planResult = await _backend.RunAsync("PLAN_RUNTIME", force: true, timeout: TimeSpan.FromMinutes(4));
            if (!planResult.Success) throw new InvalidOperationException(planResult.Error);
            var planText = CustomerCopy.Plain(planResult.Payload.String("Text"));
            var plan = planResult.Payload.TryGetProperty("Plan", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.Object ? p : default;
            var eligible = plan.ValueKind == System.Text.Json.JsonValueKind.Object && plan.Bool("Eligible");
            var state = plan.ValueKind == System.Text.Json.JsonValueKind.Object ? plan.String("PlanState") : "NO_ACTION_REQUIRED";

            if (!eligible)
            {
                RuntimeInfo.Title = state == "NO_ACTION_REQUIRED" ? "结论：不必修复" : "结论：现在不能自动修";
                RuntimeInfo.Message = string.IsNullOrWhiteSpace(planText)
                    ? "C++ 运行库和 DirectX 都可用。"
                    : planText.Replace("\r\n", " ").Replace("\n", " ").Trim();
                RuntimeInfo.Severity = state == "NO_ACTION_REQUIRED" ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
                return;
            }

            var confirmed = await PageHelpers.ConfirmAsync(
                this,
                "确认修复运行库",
                "接下来会弹出系统确认。会优先用本机已有安装包修好 C++ 运行库和 DirectX，没有再用系统安装器。",
                "继续");
            if (!confirmed) return;

            RuntimeInfo.Title = "正在修复";
            RuntimeInfo.Message = "正在修复运行库。请在系统确认窗口同意。";
            await App.Services.Workflow.RecordPlanAsync("RUNTIME", "", state, true, planText);
            await App.Services.Workflow.RecordBrokerStartAsync("RUNTIME", "");
            var result = await _broker.ExecuteAsync("RUNTIME_REPAIR", "");
            await App.Services.Workflow.RecordBrokerResultAsync("RUNTIME", "", result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "修复已返回" : "修复未完成", CustomerCopy.Plain(result.Detail));
            await RefreshLocalAsync(true);
        }
        catch (Exception ex)
        {
            App.Services.SessionLog.Bug("Runtime.Repair", ex);
            RuntimeInfo.Title = "修复出错";
            RuntimeInfo.Message = CustomerCopy.Plain(ex.Message);
            RuntimeInfo.Severity = InfoBarSeverity.Error;
        }
        finally
        {
            RefreshButton.IsEnabled = true;
            RepairButton.IsEnabled = true;
        }
    }

    private void ApplyLocalVerdict(string title)
    {
        var broken = _rows.Any(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");
        var warn = _rows.Any(x => x.Status is "WARN" or "UPDATE");
        RuntimeInfo.Title = title;
        if (broken)
        {
            RuntimeInfo.Message = "有运行库不完整。点「修复运行库」可以自动修。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else if (warn)
        {
            RuntimeInfo.Message = "可以玩游戏，但有项目版本偏低。点「修复运行库」可以更新。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else
        {
            RuntimeInfo.Message = "结论：不必修复。C++ 运行库和 DirectX 都可用。需要时仍可点「修复运行库」。";
            RuntimeInfo.Severity = InfoBarSeverity.Success;
        }
    }
}
