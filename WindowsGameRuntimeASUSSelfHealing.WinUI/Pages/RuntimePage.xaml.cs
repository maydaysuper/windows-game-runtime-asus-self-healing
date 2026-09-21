using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class RuntimePage : Page
{
    private readonly BackendService _backend = App.Services.Backend;
    private readonly BrokerService _broker = App.Services.Broker;
    private readonly ObservableCollection<ComponentItem> _rows = new();
    private readonly ObservableCollection<RuntimePackageItem> _packages = new();
    private bool _eligible;
    private string _planText = "";
    private bool _loaded;

    public RuntimePage()
    {
        InitializeComponent();
        NavigationCacheMode = NavigationCacheMode.Enabled;
        RuntimeRows.ItemsSource = _rows;
        PackageRows.ItemsSource = _packages;
        Loaded += async (_, _) =>
        {
            if (_loaded) return;
            _loaded = true;
            var cached = await App.Services.StateStore.ReadComponentStatesAsync("RUNTIME");
            foreach (var row in cached) _rows.Add(row);
            if (cached.Count > 0)
            {
                RuntimeInfo.Title = "已加载本机检测缓存";
                RuntimeInfo.Message = "来自主页最近一次健康检测；需要核对 Microsoft 最新官方包时再点击“联网对比”。";
                RuntimeInfo.Severity = cached.Any(x => x.Status is "FAIL" or "REPAIR" or "WARN" or "UPDATE") ? InfoBarSeverity.Warning : InfoBarSeverity.Success;
            }
        };
    }

    private async void OnlineButton_Click(object sender, RoutedEventArgs e) => await LoadOnlineAsync(true);

    private async Task LoadOnlineAsync(bool force)
    {
        OnlineButton.IsEnabled = false;
        RuntimeInfo.Title = "联网检测中";
        RuntimeInfo.Message = "正在核对 Microsoft HTTPS 重定向链、最终域、Authenticode、SHA256 与版本…";
        RuntimeInfo.Severity = InfoBarSeverity.Informational;
        try
        {
            using var r = await _backend.RunAsync("RUNTIME_ONLINE", force: force, timeout: TimeSpan.FromMinutes(5));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            _rows.Clear();
            foreach (var e in r.Payload.Array("Rows")) _rows.Add(PageHelpers.ToComponent(e));
            await App.Services.StateStore.UpsertComponentStatesAsync(_rows);
            _packages.Clear();
            foreach (var e in r.Payload.Array("Packages"))
                _packages.Add(new RuntimePackageItem
                {
                    Key = e.String("Key"), Version = e.String("Version"), Source = e.String("Source"), Sha256 = e.String("SHA256"),
                    Signer = e.String("Signer"), FinalUri = e.String("FinalUri"), Success = e.Bool("Success"), TrustComplete = e.Bool("TrustComplete")
                });
            var elig = r.Payload.GetProperty("Eligibility");
            _eligible = elig.Bool("Eligible");
            RuntimeInfo.Title = "资格状态：" + elig.String("State");
            RuntimeInfo.Message = elig.String("Decision");
            RuntimeInfo.Severity = _eligible ? InfoBarSeverity.Success : elig.String("State") == "NO_ACTION_REQUIRED" ? InfoBarSeverity.Informational : InfoBarSeverity.Warning;
            RepairButton.IsEnabled = _eligible;
        }
        catch (Exception ex)
        {
            _eligible = false;
            RepairButton.IsEnabled = false;
            RuntimeInfo.Title = "联网检测失败";
            RuntimeInfo.Message = ex.Message;
            RuntimeInfo.Severity = InfoBarSeverity.Error;
        }
        finally { OnlineButton.IsEnabled = true; }
    }

    private async void PlanButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            using var r = await _backend.RunAsync("PLAN_RUNTIME", force: true, timeout: TimeSpan.FromMinutes(5));
            if (!r.Success) throw new InvalidOperationException(r.Error);
            _planText = r.Payload.String("Text");
            var plan = r.Payload.GetProperty("Plan");
            _eligible = plan.Bool("Eligible");
            RepairButton.IsEnabled = _eligible;
            await App.Services.Workflow.RecordPlanAsync("RUNTIME", "", plan.String("PlanState"), _eligible, _planText);
            await PageHelpers.ShowAsync(this, "VC++ / DirectX Dry Run", _planText);
        }
        catch (Exception ex)
        {
            _eligible = false;
            RepairButton.IsEnabled = false;
            await PageHelpers.ShowAsync(this, "Dry Run 失败", ex.Message);
        }
    }

    private async void RepairButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_eligible) { await PageHelpers.ShowAsync(this, "不能执行", "当前没有通过 Repair Eligibility。"); return; }
        try
        {
            if (string.IsNullOrWhiteSpace(_planText)) await PlanButtonInternalAsync();
            if (!_eligible) return;
            if (!await PageHelpers.ConfirmAsync(this, "确认运行库修复", _planText, "通过 UAC 修复")) return;

            RepairButton.IsEnabled = false;
            await App.Services.Workflow.RecordBrokerStartAsync("RUNTIME", "");
            var result = await _broker.ExecuteAsync("RUNTIME_REPAIR");
            await App.Services.Workflow.RecordBrokerResultAsync("RUNTIME", "", result.Success, result.State, result.Detail);
            await PageHelpers.ShowAsync(this, result.Success ? "修复流程已提交" : "修复未完成", result.Detail);
            await LoadOnlineAsync(true);
        }
        catch (Exception ex)
        {
            await App.Services.Workflow.RecordBrokerResultAsync("RUNTIME", "", false, "FAILED", ex.Message);
            await PageHelpers.ShowAsync(this, "修复流程异常", ex.Message);
        }
        finally { RepairButton.IsEnabled = _eligible; }
    }

    private async Task PlanButtonInternalAsync()
    {
        using var r = await _backend.RunAsync("PLAN_RUNTIME", force: true, timeout: TimeSpan.FromMinutes(5));
        if (!r.Success) { _eligible = false; return; }
        _planText = r.Payload.String("Text");
        var plan = r.Payload.GetProperty("Plan");
        _eligible = plan.Bool("Eligible");
        await App.Services.Workflow.RecordPlanAsync("RUNTIME", "", plan.String("PlanState"), _eligible, _planText);
    }
}
