using System.Windows;
using System.Windows.Controls;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        var build = App.Services.Backend.GetBuildIdentity();
        VersionText.Text = $"WPF · v{build.Version}";
        BuildText.Text = $"{build.BuildId} · {build.WindowsAppSdk} · .NET {build.DotNet} · {build.Language}";
        NavigateTag("overview");
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string tag })
            NavigateTag(tag);
    }

    private void NavigateTag(string tag)
    {
        Page page = tag switch
        {
            "overview" => new OverviewPage(),
            "asus" => new SafetyPage(),
            "runtime" => new RuntimePage(),
            "crash" => new CrashPage(),
            "reports" => new ReportsPage(),
            _ => new OverviewPage()
        };
        try { ContentFrame.Navigate(page); }
        catch (Exception ex)
        {
            StartupGuard.Write("Navigate:" + tag, ex);
            ContentFrame.Content = new TextBox
            {
                Text = "页面加载失败（" + tag + "）\n\n" + ex,
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(24)
            };
        }
    }
}
