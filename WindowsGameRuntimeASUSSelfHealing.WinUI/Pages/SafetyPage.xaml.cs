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
            if (!r.Success) throw new InvalidOperationException(r.Error);

            var codes = r.Payload.StringArray("ActiveErrorCodes");
            var updateCodes = codes.Where(IsAsusUpdateError).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            var components = r.Payload.Array("Components")
                .Select(PageHelpers.ToComponent)
                .Where(x => AsusGroups.Contains(x.Group, StringComparer.OrdinalIgnoreCase))
                .ToArray();

            foreach (var code in updateCodes)
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = "奥创更新错误 " + code,
                    Status = "FAIL",
                    Detail = code is "4151" or "4152"
                        ? "Armoury Crate 正在报 " + code + "。这是奥创组件更新失败，不是系统健康体检。"
                        : "奥创相关错误码 " + code + "。"
                });
            }

            foreach (var row in components.Where(x => x.Status is "FAIL" or "REPAIR" or "WARN" or "UPDATE" or "NEEDS_REPAIR"))
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = row.Name,
                    Status = row.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR" ? "FAIL" : "WARN",
                    Detail = string.IsNullOrWhiteSpace(row.ErrorCode)
                        ? row.Detail
                        : "错误码 " + row.ErrorCode + " · " + row.Detail
                });
            }

            if (_asusErrors.Count == 0)
            {
                _asusErrors.Add(new PreflightItem
                {
                    Name = "当前没有奥创更新错误",
                    Status = "PASS",
                    Detail = "没有命中 4151 / 4152，也没有已验证奥创组件处于失败状态。"
                });
                PlanInfo.Title = "奥创结论：不必修复";
                PlanInfo.Message = "当前 Armoury Crate 没有更新错误。首页系统健康是总览，这里只看奥创。";
                PlanInfo.Severity = InfoBarSeverity.Success;
            }
            else if (updateCodes.Length > 0)
            {
                PlanInfo.Title = "奥创结论：发现更新错误";
                PlanInfo.Message = "命中 " + string.Join(" / ", updateCodes) + "。点「检测奥创更新错误」生成是否可自动修的方案。未知新版本只诊断。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
            }
            else
            {
                PlanInfo.Title = "奥创结论：有组件需要关注";
                PlanInfo.Message = "没有 4151/4152，但有奥创组件状态异常。请看左侧条目。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
            }
        }
        catch (Exception ex)
        {
            _asusErrors.Clear();
            PlanInfo.Title = "奥创检测失败";
            PlanInfo.Severity = InfoBarSeverity.Error;
            PlanInfo.Message = ex.Message;
            App.Services.SessionLog.Bug("ASUS.Errors", ex);
        }
    }

    private static bool IsAsusUpdateError(string code)
    {
        var c = code.Trim();
        return c.Contains("4151", StringComparison.OrdinalIgnoreCase)
            || c.Contains("4152", StringComparison.OrdinalIgnoreCase)
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
            var state = plan.ValueKind == System.Text.Json.JsonValueKind.Object ? plan.String("PlanState") : "NO_ACTION_REQUIRED";
            UpdatePlanInfo(state, _eligible);
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
            SetPlanFailure(ex.Message);
        }
    }

    private void UpdatePlanInfo(string state, bool eligible)
    {
        ExecuteButton.IsEnabled = eligible;
        if (eligible)
        {
            PlanInfo.Title = "奥创结论：可以安全修复";
            PlanInfo.Message = "已通过修复资格。执行时 Broker 会再诊断一次。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }

        if (state == "NO_ACTION_REQUIRED")
        {
            PlanInfo.Title = "奥创结论：不必修复";
            PlanInfo.Message = "当前没有命中已验证的奥创自动修复组合。不是系统健康冲突，就是现在没有 4151/4152 可修。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }

        PlanInfo.Title = "奥创结论：" + state;
        PlanInfo.Message = "当前不会改系统。请看右侧方案里的原因。未知奥创版本只诊断。";
        PlanInfo.Severity = InfoBarSeverity.Warning;
    }

    private void SetPlanFailure(string error)
    {
        _eligible = false;
        ExecuteButton.IsEnabled = false;
        PlanInfo.Title = "计划生成失败";
        PlanInfo.Message = error;
        PlanInfo.Severity = InfoBarSeverity.Error;
    }

    private async void ExecuteButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_eligible) return;
        var confirmed = await PageHelpers.ConfirmAsync(this, "确认执行修复", PlanText.Text + "\n\nElevated Broker 会在管理员上下文重新执行完整 Repair Eligibility。", "通过 UAC 执行");
        if (!confirmed) return;
        ExecuteButton.IsEnabled = false;
        var action = _planType == "RUNTIME" ? "RUNTIME_REPAIR" : "ASUS_REPAIR";
        try
        {
            await App.Services.Workflow.RecordBrokerStartAsync(_planType, _planGroup);
            var result = await _broker.ExecuteAsync(action, _planGroup);
            await App.Services.Workflow.RecordBrokerResultAsync(_planType, _planGroup, result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "Broker 已返回" : "Broker 未完成", result.Detail);
            _eligible = false;
        }
        catch (Exception ex)
        {
            App.Services.SessionLog.Bug("ASUS.Repair", ex);
            await App.Services.Workflow.RecordBrokerResultAsync(_planType, _planGroup, false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "Broker 错误", ex.Message);
        }
        finally
        {
            ExecuteButton.IsEnabled = _eligible;
            await LoadAsusErrorsAsync();
        }
    }
}
