using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

public sealed partial class DeepTestPage : Page
{
    private readonly ObservableCollection<DeepTestItem> _rows=new();
    private readonly BackendService _backend=App.Services.Backend;
    public DeepTestPage(){InitializeComponent();DeepList.ItemsSource=_rows;}
    private async void RunButton_Click(object sender,RoutedEventArgs e)
    {
        RunButton.IsEnabled=false;DeepInfo.Title="后台测试中";DeepInfo.Message="可以继续切换页面，测试完成后结果会返回本页。";DeepInfo.Severity=InfoBarSeverity.Informational;
        try{
            using var r=await _backend.RunAsync("DEEP",timeout:TimeSpan.FromMinutes(6));
            if(!r.Success)throw new InvalidOperationException(r.Error);
            _rows.Clear();foreach(var x in r.Payload.Array("Rows"))_rows.Add(new DeepTestItem{Category=x.String("Category"),Test=x.String("Test"),Status=x.String("Status"),Detail=x.String("Detail")});
            var fail=_rows.Count(x=>x.Status=="FAIL");var warn=_rows.Count(x=>x.Status=="WARN");
            DeepInfo.Title=$"完成：FAIL={fail} WARN={warn}";DeepInfo.Message="测试结果是诊断证据，不会自动删除驱动或执行 DDU。";DeepInfo.Severity=fail>0?InfoBarSeverity.Error:warn>0?InfoBarSeverity.Warning:InfoBarSeverity.Success;
        }catch(Exception ex){DeepInfo.Title="测试失败";DeepInfo.Message=ex.Message;DeepInfo.Severity=InfoBarSeverity.Error;}finally{RunButton.IsEnabled=true;}
    }
}
