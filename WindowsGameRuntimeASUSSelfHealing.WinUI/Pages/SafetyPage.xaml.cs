using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class SafetyPage : Page
{
    private static readonly string[] AsusGroups = ["PV", "HOLTEK", "ENE"];
    private readonly BackendService _backend = App.Services.Backend;
    private readonly BrokerService _broker = App.Services.Broker;
    private readonly ObservableCollection<PreflightItem> _asusErrors = new();
    private string _planType = "";
    private string _planGroup = "";
    private bool _eligible;
    private bool _launchEligible;
    private bool _loaded;

    public SafetyPage()
    {
        InitializeComponent();
        PreflightList.ItemsSource = _asusErrors;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            await LoadAsusErrorsAsync();
        };
    }

    private async Task LoadAsusErrorsAsync()
    {
        try
        {
            using var r = await _backend.RunAsync("DASHBOARD", force: true, timeout: TimeSpan.FromMinutes(2));
            _asusErrors.Clear();
            _launchEligible = false;
            if (!r.Success) throw new InvalidOperationException(r.Error);

            var codes = r.Payload.StringArray("ActiveErrorCodes");
            var updateCodes = codes.Where(IsAsusUpdateError).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            var launchNeeded = r.Payload.Bool("ArmouryCrateNeedsRepair");
            var launchIssue = r.Payload.String("ArmouryCrateIssue");
            var components = r.Payload.Array("Components")
                .Select(PageHelpers.ToComponent)
                .Where(x => AsusGroups.Contains(x.Group, StringComparer.OrdinalIgnoreCase))
                .ToArray();

            if (launchNeeded || codes.Any(c => c.Contains("501", StringComparison.OrdinalIgnoreCase)))
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = codes.Any(c => c.Contains("501", StringComparison.OrdinalIgnoreCase)) ? "安装出现 501" : "奥创打不开",
                    Status = "FAIL",
                    Detail = string.IsNullOrWhiteSpace(launchIssue)
                        ? "安装失败或装完打不开。可以全自动修：清残留、检查 C++、拉起服务、再打开。"
                        : launchIssue
                });
                _launchEligible = true;
            }

            foreach (var code in updateCodes)
            {
                var isKnown = code.Contains("4151", StringComparison.OrdinalIgnoreCase)
                    || code.Contains("4152", StringComparison.OrdinalIgnoreCase);
                if (code.Contains("501", StringComparison.OrdinalIgnoreCase) || code.Contains("601", StringComparison.OrdinalIgnoreCase))
                    continue;
                _asusErrors.Add(new PreflightItem
                {
                    Name = isKnown ? "奥创更新失败" : "奥创相关错误",
                    Status = "FAIL",
                    Detail = isKnown
                        ? "奥创组件更新没有成功。这不是系统体检问题，到这里处理。"
                        : "奥创报告了安装错误。"
                });
            }

            foreach (var row in components.Where(x => x.Status is "FAIL" or "REPAIR" or "WARN" or "UPDATE" or "NEEDS_REPAIR"))
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = row.DisplayName,
                    Status = row.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR" ? "FAIL" : "WARN",
                    Detail = row.ResultLine
                });
            }

            if (_asusErrors.Count == 0)
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = "当前没有奥创问题",
                    Status = "PASS",
                    Detail = "没有 501、打不开或更新失败。不必修复。"
                });
                PlanInfo.Title = "结论：不必修复";
                PlanInfo.Message = "奥创现在没有安装失败、打不开或更新错误。";
                PlanInfo.Severity = InfoBarSeverity.Success;
                AutoRepairButton.IsEnabled = false;
            }
            else if (_launchEligible)
            {
                PlanInfo.Title = "结论：可以全自动修复";
                PlanInfo.Message = "501 或打不开可以一键修。会弹出系统确认。笔记本和台式机都能用。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
                AutoRepairButton.IsEnabled = true;
            }
            else if (updateCodes.Length > 0)
            {
                PlanInfo.Title = "结论：发现更新错误";
                PlanInfo.Message = "点「检测问题」看能不能修灯效更新。未知新版本只诊断，不套旧方案。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
                AutoRepairButton.IsEnabled = false;
            }
            else
            {
                PlanInfo.Title = "结论：有组件需要关注";
                PlanInfo.Message = "没有 501 或打不开，但有奥创组件状态异常。请看左侧。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
                AutoRepairButton.IsEnabled = false;
            }
        }
        catch (Exception ex)
        {
            _asusErrors.Clear();
            PlanInfo.Title = "检测失败";
            PlanInfo.Severity = InfoBarSeverity.Error;
            PlanInfo.Message = CustomerCopy.Plain(ex.Message);
            App.Services.SessionLog.Bug("ASUS.Errors", ex);
        }
    }

    private static bool IsAsusUpdateError(string code)
    {
        var c = code.Trim();
        return c.Contains("4151", StringComparison.OrdinalIgnoreCase)
            || c.Contains("4152", StringComparison.OrdinalIgnoreCase)
            || c.Contains("501", StringComparison.OrdinalIgnoreCase)
            || c.Contains("601", StringComparison.OrdinalIgnoreCase)
            || c.Contains("1603", StringComparison.OrdinalIgnoreCase)
            || c.Contains("1618", StringComparison.OrdinalIgnoreCase)
            || c.Contains("1721", StringComparison.OrdinalIgnoreCase);
    }

    private string SelectedGroup()
    {
        if (GroupCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag && tag != "AUTO") return tag;
        return "";
    }

    private async void AsusPlan_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var group = SelectedGroup();
            await LoadAsusErrorsAsync();
            using var r = await _backend.RunAsync("PLAN_ASUS", group: group, force: true, timeout: TimeSpan.FromMinutes(4));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            PlanText.Text = r.Payload.String("Text");
            _planGroup = r.Payload.String("RecommendedGroup");
            _planType = "ASUS";
            var plan = r.Payload.TryGetProperty("Plan", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.Object ? p : default;
            _eligible = plan.ValueKind == System.Text.Json.JsonValueKind.Object && plan.Bool("Eligible");
            _launchEligible = r.Payload.Bool("LaunchEligible") || _launchEligible;
            var state = plan.ValueKind == System.Text.Json.JsonValueKind.Object ? plan.String("PlanState") : "NO_ACTION_REQUIRED";
            UpdatePlanInfo(state, _eligible, _launchEligible);
            try
            {
                await App.Services.Workflow.RecordPlanAsync(_planType, _planGroup, state, _eligible, PlanText.Text);
            }
            catch (Exception wf)
            {
                App.Services.SessionLog.Bug("ASUS.RecordPlan", wf);
            }
        }
        catch (Exception ex)
        {
            App.Services.SessionLog.Bug("ASUS.Plan", ex);
            SetPlanFailure(CustomerCopy.Plain(ex.Message));
        }
    }

    private void UpdatePlanInfo(string state, bool eligible, bool launchEligible)
    {
        ExecuteButton.IsEnabled = eligible && !launchEligible;
        AutoRepairButton.IsEnabled = launchEligible || eligible;
        if (launchEligible)
        {
            PlanInfo.Title = "结论：可以全自动修复";
            PlanInfo.Message = "点「全自动修复」后会弹出系统确认。会修 501 / 打不开，有已验证灯效错误也会一起修。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }
        if (eligible)
        {
            PlanInfo.Title = "结论：可以安全修复";
            PlanInfo.Message = "点「全自动修复」或「执行灯效修复」后会弹出系统确认。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }

        if (state == "NO_ACTION_REQUIRED")
        {
            PlanInfo.Title = "结论：不必修复";
            PlanInfo.Message = "现在没有 501、打不开或可自动修的奥创更新错误。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }

        PlanInfo.Title = "结论：暂不修复";
        PlanInfo.Message = "当前不会改系统。请看右侧原因。未知奥创版本只诊断。";
        PlanInfo.Severity = InfoBarSeverity.Warning;
    }

    private void SetPlanFailure(string error)
    {
        _eligible = false;
        _launchEligible = false;
        ExecuteButton.IsEnabled = false;
        AutoRepairButton.IsEnabled = false;
        PlanInfo.Title = "检测失败";
        PlanInfo.Message = error;
        PlanInfo.Severity = InfoBarSeverity.Error;
    }

    private async void AutoRepairButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_launchEligible && !_eligible) return;
        var confirmed = await PageHelpers.ConfirmAsync(this, "全自动修复奥创", "接下来会弹出系统确认。会清理安装残留、检查 C++、拉起奥创服务并尝试打开。不会卸显卡驱动，也不会套未知新版本的旧方案。", "开始修复");
        if (!confirmed) return;
        AutoRepairButton.IsEnabled = false;
        ExecuteButton.IsEnabled = false;
        try
        {
            await App.Services.Workflow.RecordBrokerStartAsync("ASUS_CRATE", _planGroup);
            var group = _planGroup is "PV" or "HOLTEK" or "ENE" ? _planGroup : SelectedGroup();
            var result = await _broker.ExecuteAsync("ASUS_CRATE_REPAIR", group);
            await App.Services.Workflow.RecordBrokerResultAsync("ASUS_CRATE", group, result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "修复已返回" : "修复未完成", CustomerCopy.Plain(result.Detail));
            _launchEligible = false;
            _eligible = false;
        }
        catch (Exception ex)
        {
            App.Services.SessionLog.Bug("ASUS.CrateRepair", ex);
            await App.Services.Workflow.RecordBrokerResultAsync("ASUS_CRATE", _planGroup, false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "修复出错", CustomerCopy.Plain(ex.Message));
        }
        finally
        {
            await LoadAsusErrorsAsync();
        }
    }

    private async void ExecuteButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_eligible) return;
        var confirmed = await PageHelpers.ConfirmAsync(this, "确认执行修复", "接下来会弹出系统确认。只会按已验证步骤修奥创更新错误。", "继续");
        if (!confirmed) return;
        ExecuteButton.IsEnabled = false;
        var action = _planType == "RUNTIME" ? "RUNTIME_REPAIR" : "ASUS_REPAIR";
        try
        {
            await App.Services.Workflow.RecordBrokerStartAsync(_planType, _planGroup);
            var result = await _broker.ExecuteAsync(action, _planGroup);
            await App.Services.Workflow.RecordBrokerResultAsync(_planType, _planGroup, result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "修复已返回" : "修复未完成", CustomerCopy.Plain(result.Detail));
            _eligible = false;
        }
        catch (Exception ex)
        {
            App.Services.SessionLog.Bug("ASUS.Repair", ex);
            await App.Services.Workflow.RecordBrokerResultAsync(_planType, _planGroup, false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "修复出错", CustomerCopy.Plain(ex.Message));
        }
        finally
        {
            ExecuteButton.IsEnabled = _eligible;
            await LoadAsusErrorsAsync();
        }
    }
}
