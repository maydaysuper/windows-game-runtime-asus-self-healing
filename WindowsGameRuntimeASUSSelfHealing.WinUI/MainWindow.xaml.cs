using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        if (!App.Services.Resources.Profile.PreferBelowNormalPriority)
        {
            try { SystemBackdrop = new MicaBackdrop(); } catch { }
        }

        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
            var appWindow = AppWindow.GetFromWindowId(windowId);
            appWindow.Resize(new SizeInt32(1360, 860));
        }
        catch { }

        var build = App.Services.Backend.GetBuildIdentity();
        VersionText.Text = $"WinUI 3 · v{build.Version}";
        BuildText.Text = $"{build.BuildId} · Windows App SDK {build.WindowsAppSdk} · .NET {build.DotNet} · {build.Language}";

        NavView.SelectedItem = OverviewItem;
        ContentFrame.Navigate(typeof(OverviewPage));
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag) return;
        var page = tag switch
        {
            "overview" => typeof(OverviewPage),
            "asus" => typeof(SafetyPage),
            "runtime" => typeof(RuntimePage),
            "crash" => typeof(CrashPage),
            "reports" => typeof(ReportsPage),
            _ => typeof(OverviewPage)
        };
        if (ContentFrame.CurrentSourcePageType != page)
            ContentFrame.Navigate(page);
    }
}
