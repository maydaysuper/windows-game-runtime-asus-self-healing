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
    private bool _repairing;

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
            await RefreshOnlineAsync(true);
        };
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshOnlineAsync(true);

    private async Task RefreshOnlineAsync(bool promptRepair)
    {
        RefreshButton.IsEnabled = false;
        RepairButton.IsEnabled = false;
        RuntimeInfo.Title = "正在检测";
        RuntimeInfo.Message = "正在检查本机 C++ 文件，并联网对比官方版本。";
        RuntimeInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            using var r = await _backend.RunAsync("RUNTIME_ONLINE", force: true, timeout: TimeSpan.FromMinutes(4));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            _rows.Clear();
            foreach (var e in r.Payload.Array("Rows"))
            {
                var row = PageHelpers.ToComponent(e);
                if (row.Group.Equals("RUNTIME", StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(row.Group))
                    _rows.Add(row);
            }
            await App.Services.StateStore.UpsertComponentStatesAsync(_rows);
            ApplyLocalVerdict(r.Payload.String("Message"));
            var eligible = r.Payload.TryGetProperty("Eligibility", out var elig)
                && elig.ValueKind == System.Text.Json.JsonValueKind.Object
                && elig.Bool("Eligible");
            if (promptRepair && eligible && NeedsAutoRepair())
                await TryRepairAsync(autoPrompt: true);
        }
        catch (Exception ex)
        {
            RuntimeInfo.Title = "检测失败";
            RuntimeInfo.Message = CustomerCopy.Plain(ex.Message);
            RuntimeInfo.Severity = InfoBarSeverity.Error;
            App.Services.SessionLog.Bug("Runtime.Online", ex);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
            RepairButton.IsEnabled = true;
        }
    }

    private bool NeedsAutoRepair() =>
        _rows.Any(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR" or "UPDATE");

    private async void RepairButton_Click(object sender, RoutedEventArgs e) => await TryRepairAsync(autoPrompt: false);

    private async Task TryRepairAsync(bool autoPrompt)
    {
        if (_repairing) return;
        _repairing = true;
        RefreshButton.IsEnabled = false;
        RepairButton.IsEnabled = false;
        RuntimeInfo.Title = "正在判断能不能修";
        RuntimeInfo.Message = "先看本机文件能不能用，再对比官方版本。";
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
                autoPrompt ? "和官方不一样，现在修复？" : "确认修复运行库",
                "会把偏低或不完整的 C++ 运行库更新到官方版本，并修好缺失的 DirectX 组件。",
                "立即修复");
            if (!confirmed) return;

            RuntimeInfo.Title = "正在修复";
            RuntimeInfo.Message = "正在更新运行库。请在系统确认窗口同意。";
            await App.Services.Workflow.RecordPlanAsync("RUNTIME", "", state, true, planText);
            await App.Services.Workflow.RecordBrokerStartAsync("RUNTIME", "");
            var result = await _broker.ExecuteAsync("RUNTIME_REPAIR", "");
            await App.Services.Workflow.RecordBrokerResultAsync("RUNTIME", "", result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "修复已返回" : "修复未完成", CustomerCopy.Plain(result.Detail));
            _repairing = false;
            await RefreshOnlineAsync(false);
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
            _repairing = false;
            RefreshButton.IsEnabled = true;
            RepairButton.IsEnabled = true;
        }
    }

    private void ApplyLocalVerdict(string title)
    {
        var broken = _rows.Any(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");
        var warn = _rows.Any(x => x.Status is "WARN" or "UPDATE");
        var heading = string.IsNullOrWhiteSpace(title) ? "检测完成" : title;
        if (heading.Length > 24) heading = "检测完成";
        RuntimeInfo.Title = heading;
        if (broken)
        {
            RuntimeInfo.Message = "有运行库不完整。正在准备修复。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else if (warn)
        {
            RuntimeInfo.Message = NeedsAutoRepair()
                ? "和官方版本不一样。正在准备更新到官方版本。"
                : "本机可用。这次没连上官方源，无法确认是否最新。";
            RuntimeInfo.Severity = InfoBarSeverity.Warning;
        }
        else
        {
            RuntimeInfo.Message = "结论：不必修复。已和官方一致，或本机可用。";
            RuntimeInfo.Severity = InfoBarSeverity.Success;
        }
    }
}
