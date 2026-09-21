using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Windows.UI.Text;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public sealed partial class MainWindow : Window
{
    private Grid AppTitleBar = null!;
    private TextBlock VersionText = null!;
    private TextBlock StatusText = null!;
    private TextBlock BuildText = null!;
    private Frame ContentFrame = null!;
    private NavigationViewItem OverviewItem = null!;
    private NavigationView? NavView;
    private ProgressRing? GlobalProgress;

    public MainWindow()
    {
        try { InitializeComponent(); }
        catch (Exception ex) { StartupGuard.Write("MainWindow.InitializeComponent", ex); }

        BuildShell();

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

        NavigateTag("overview");
    }

    private void BuildShell()
    {
        AppTitleBar = new Grid { Height = 48, Padding = new Thickness(16, 0, 16, 0) };
        AppTitleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        AppTitleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        AppTitleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var titleIcon = new FontIcon { Glyph = "\uE7BA", FontSize = 18, VerticalAlignment = VerticalAlignment.Center };
        var titlePanel = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Spacing = 10 };
        Grid.SetColumn(titlePanel, 2);
        titlePanel.Children.Add(new TextBlock
        {
            Text = "Windows 游戏运行环境自愈中心",
            FontWeight = new FontWeight { Weight = 600 },
            FontSize = 15,
            VerticalAlignment = VerticalAlignment.Center
        });
        VersionText = new TextBlock { FontSize = 11, FontWeight = new FontWeight { Weight = 600 }, Padding = new Thickness(8, 2, 8, 2) };
        var versionBorder = new Border
        {
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(ColorHelper.FromArgb(255, 96, 165, 250)),
            Child = VersionText
        };
        titlePanel.Children.Add(versionBorder);
        AppTitleBar.Children.Add(titleIcon);
        AppTitleBar.Children.Add(titlePanel);

        ContentFrame = new Frame { CacheSize = 7 };
        OverviewItem = NavItem("系统健康", "overview", "\uE9D9");
        FrameworkElement navHost;
        try
        {
            NavView = new NavigationView
            {
                IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
                IsSettingsVisible = false,
                PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
                IsPaneOpen = true,
                OpenPaneLength = 220,
                Content = ContentFrame
            };
            NavView.MenuItems.Add(OverviewItem);
            NavView.MenuItems.Add(NavItem("ASUS 奥创中心", "asus", "\uEA18"));
            NavView.MenuItems.Add(NavItem("游戏运行库", "runtime", "\uE90F"));
            NavView.MenuItems.Add(NavItem("崩溃 / Dump", "crash", "\uE7BA"));
            NavView.MenuItems.Add(NavItem("报告中心", "reports", "\uE9D2"));
            NavView.SelectionChanged += NavView_SelectionChanged;
            navHost = NavView;
        }
        catch (Exception ex)
        {
            StartupGuard.Write("NavigationView", ex);
            navHost = BuildButtonNav();
        }

        var muted = new SolidColorBrush(ColorHelper.FromArgb(255, 100, 116, 139));
        StatusText = new TextBlock { Text = "就绪 · 后台任务按硬件自适应限流", Foreground = muted, VerticalAlignment = VerticalAlignment.Center };
        BuildText = new TextBlock { Foreground = muted, VerticalAlignment = VerticalAlignment.Center };
        var status = new Grid { Padding = new Thickness(14, 8, 14, 8) };
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        try
        {
            GlobalProgress = new ProgressRing { Width = 18, Height = 18, IsActive = false, Visibility = Visibility.Collapsed };
            status.Children.Add(GlobalProgress);
        }
        catch (Exception ex) { StartupGuard.Write("ProgressRing", ex); }
        Grid.SetColumn(StatusText, 2);
        Grid.SetColumn(BuildText, 3);
        status.Children.Add(StatusText);
        status.Children.Add(BuildText);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(navHost, 1);
        Grid.SetRow(status, 2);
        root.Children.Add(AppTitleBar);
        root.Children.Add(navHost);
        root.Children.Add(status);
        Content = root;
    }

    private FrameworkElement BuildButtonNav()
    {
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Padding = new Thickness(16, 8, 16, 8) };
        foreach (var (label, tag) in new[]
        {
            ("系统健康", "overview"),
            ("ASUS 奥创中心", "asus"),
            ("游戏运行库", "runtime"),
            ("崩溃 / Dump", "crash"),
            ("报告中心", "reports")
        })
        {
            var button = new Button { Content = label, Tag = tag };
            button.Click += (_, _) => NavigateTag(tag);
            bar.Children.Add(button);
        }
        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(ContentFrame, 1);
        grid.Children.Add(bar);
        grid.Children.Add(ContentFrame);
        return grid;
    }

    private static NavigationViewItem NavItem(string content, string tag, string glyph) => new()
    {
        Content = content,
        Tag = tag,
        Icon = new FontIcon { FontFamily = new FontFamily("Segoe Fluent Icons"), Glyph = glyph }
    };

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is string tag)
            NavigateTag(tag);
    }

    private void NavigateTag(string tag)
    {
        var page = tag switch
        {
            "overview" => typeof(OverviewPage),
            "asus" => typeof(SafetyPage),
            "runtime" => typeof(RuntimePage),
            "crash" => typeof(CrashPage),
            "reports" => typeof(ReportsPage),
            _ => typeof(OverviewPage)
        };
        try
        {
            if (ContentFrame.CurrentSourcePageType != page)
                ContentFrame.Navigate(page);
            if (NavView is not null && tag == "overview")
                NavView.SelectedItem = OverviewItem;
        }
        catch (Exception ex)
        {
            StartupGuard.Write("Navigate:" + tag, ex);
            ContentFrame.Content = new ScrollViewer
            {
                Content = new TextBlock
                {
                    Text = "页面加载失败（" + tag + "）\n\n" + ex,
                    TextWrapping = TextWrapping.Wrap,
                    Margin = new Thickness(24),
                    IsTextSelectionEnabled = true
                }
            };
        }
    }
}
