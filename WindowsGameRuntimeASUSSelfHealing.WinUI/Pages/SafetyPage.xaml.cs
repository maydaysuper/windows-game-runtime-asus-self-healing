using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class SafetyPage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private readonly BrokerService _broker = App.Services.Broker;
    private readonly ObservableCollection<PreflightItem> _preflight = new();
    private string _planType = "";
    private string _planGroup = "";
    private bool _eligible;
    private bool _loaded;

    public SafetyPage()
    {
        InitializeComponent();
        NavigationCacheMode = NavigationCacheMode.Enabled;
        PreflightList.ItemsSource = _preflight;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            await LoadPreflightAsync();
        };
    }

    private async Task LoadPreflightAsync(string group = "")
    {
        try
        {
            using var r = await _backend.RunAsync("PREFLIGHT", group: group, timeout: TimeSpan.FromMinutes(2));
            _preflight.Clear();
            if (!r.Success) throw new InvalidOperationException(r.Error);
            foreach (var row in r.Payload.Array("Rows")) _preflight.Add(PageHelpers.ToPreflight(row));
        }
        catch (Exception ex)
        {
            _preflight.Clear();
            PlanInfo.Title = "环境预检失败";
            PlanInfo.Severity = InfoBarSeverity.Error;
            PlanInfo.Message = ex.Message;
        }
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
            await LoadPreflightAsync(group);
            using var r = await _backend.RunAsync("PLAN_ASUS", group: group, force: true, timeout: TimeSpan.FromMinutes(4));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            PlanText.Text = r.Payload.String("Text");
            _planGroup = r.Payload.String("RecommendedGroup");
            _planType = "ASUS";
            var plan = r.Payload.TryGetProperty("Plan", out var p) && p.ValueKind == System.Text.Json.JsonValueKind.Object ? p : default;
            _eligible = plan.ValueKind == System.Text.Json.JsonValueKind.Object && plan.Bool("Eligible");
            var state = plan.ValueKind == System.Text.Json.JsonValueKind.Object ? plan.String("PlanState") : "NO_ACTION_REQUIRED";
            UpdatePlanInfo(state, _eligible);
            await App.Services.Workflow.RecordPlanAsync(_planType, _planGroup, state, _eligible, PlanText.Text);
        }
        catch (Exception ex) { SetPlanFailure(ex.Message); }
    }

    private void UpdatePlanInfo(string state, bool eligible)
    {
        ExecuteButton.IsEnabled = eligible;
        PlanInfo.Title = "计划状态：" + state;
        PlanInfo.Message = eligible ? "修复资格与环境门禁均通过。执行时 Broker 会再次重新诊断并二次校验。" : "当前计划不会执行系统修改。请查看右侧 Dry Run 的原因。";
        PlanInfo.Severity = eligible ? InfoBarSeverity.Success : state == "NO_ACTION_REQUIRED" ? InfoBarSeverity.Informational : InfoBarSeverity.Warning;
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
            await App.Services.Workflow.RecordBrokerResultAsync(_planType, _planGroup, false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "Broker 错误", ex.Message);
        }
        finally
        {
            ExecuteButton.IsEnabled = _eligible;
            await LoadPreflightAsync(_planGroup);
        }
    }
}
