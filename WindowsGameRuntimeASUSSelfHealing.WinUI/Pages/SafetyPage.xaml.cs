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
                var isKnown = code.Contains("4151", StringComparison.OrdinalIgnoreCase)
                    || code.Contains("4152", StringComparison.OrdinalIgnoreCase);
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
                    Name = "当前没有奥创更新错误",
                    Status = "PASS",
                    Detail = "奥创现在没有更新失败。不必修复。"
                });
                PlanInfo.Title = "结论：不必修复";
                PlanInfo.Message = "奥创没有更新错误。";
                PlanInfo.Severity = InfoBarSeverity.Success;
            }
            else if (updateCodes.Length > 0)
            {
                PlanInfo.Title = "结论：发现更新错误";
                PlanInfo.Message = "点「检测更新错误」看能不能自动修。未知新版本只诊断，不套旧方案。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
            }
            else
            {
                PlanInfo.Title = "结论：有组件需要关注";
                PlanInfo.Message = "没有更新失败，但有奥创组件状态异常。请看左侧。";
                PlanInfo.Severity = InfoBarSeverity.Warning;
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
            SetPlanFailure(CustomerCopy.Plain(ex.Message));
        }
    }

    private void UpdatePlanInfo(string state, bool eligible)
    {
        ExecuteButton.IsEnabled = eligible;
        if (eligible)
        {
            PlanInfo.Title = "结论：可以安全修复";
            PlanInfo.Message = "点「执行安全修复」后会弹出系统确认。";
            PlanInfo.Severity = InfoBarSeverity.Success;
            return;
        }

        if (state == "NO_ACTION_REQUIRED")
        {
            PlanInfo.Title = "结论：不必修复";
            PlanInfo.Message = "现在没有可自动修的奥创更新错误。";
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
        ExecuteButton.IsEnabled = false;
        PlanInfo.Title = "检测失败";
        PlanInfo.Message = error;
        PlanInfo.Severity = InfoBarSeverity.Error;
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
