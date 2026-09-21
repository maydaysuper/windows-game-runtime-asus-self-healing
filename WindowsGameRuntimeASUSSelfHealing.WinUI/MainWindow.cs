using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Windows.UI.Text;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public sealed class MainWindow : Window
{
    private readonly Frame _content = new() { CacheSize = 7 };
    private readonly TextBlock _version = new() { FontSize = 11, FontWeight = new FontWeight { Weight = 600 }, Padding = new Thickness(8, 2, 8, 2) };
    private readonly TextBlock _status = new() { Text = "就绪 · 后台任务按硬件自适应限流" };
    private readonly TextBlock _build = new();
    private readonly Grid _titleBar = new() { Height = 48, Padding = new Thickness(16, 0, 16, 0) };

    public MainWindow()
    {
        Title = "Windows 游戏运行环境自愈中心";
        Content = BuildShell();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(_titleBar);
        if (!App.Services.Resources.Profile.PreferBelowNormalPriority)
        {
            try { SystemBackdrop = new MicaBackdrop(); } catch { }
        }

        try
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
            AppWindow.GetFromWindowId(windowId).Resize(new SizeInt32(1360, 860));
        }
        catch { }

        var build = App.Services.Backend.GetBuildIdentity();
        _version.Text = $"WinUI 3 · v{build.Version}";
        _build.Text = $"{build.BuildId} · Windows App SDK {build.WindowsAppSdk} · .NET {build.DotNet} · {build.Language}";
        NavigateTag("overview");
    }

    private FrameworkElement BuildShell()
    {
        _titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        _titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var titlePanel = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Spacing = 10 };
        Grid.SetColumn(titlePanel, 2);
        titlePanel.Children.Add(new TextBlock
        {
            Text = "Windows 游戏运行环境自愈中心",
            FontSize = 15,
            FontWeight = new FontWeight { Weight = 600 },
            VerticalAlignment = VerticalAlignment.Center
        });
        titlePanel.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(ColorHelper.FromArgb(255, 96, 165, 250)),
            Child = _version
        });
        _titleBar.Children.Add(titlePanel);

        var nav = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Padding = new Thickness(16, 8, 16, 8) };
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
            nav.Children.Add(button);
        }

        var muted = new SolidColorBrush(ColorHelper.FromArgb(255, 100, 116, 139));
        _status.Foreground = muted;
        _status.VerticalAlignment = VerticalAlignment.Center;
        _build.Foreground = muted;
        _build.VerticalAlignment = VerticalAlignment.Center;
        var status = new Grid { Padding = new Thickness(14, 8, 14, 8) };
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        status.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(_build, 1);
        status.Children.Add(_status);
        status.Children.Add(_build);

        var body = new Grid();
        body.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        body.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(_content, 1);
        body.Children.Add(nav);
        body.Children.Add(_content);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(body, 1);
        Grid.SetRow(status, 2);
        root.Children.Add(_titleBar);
        root.Children.Add(body);
        root.Children.Add(status);
        return root;
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
            if (_content.CurrentSourcePageType != page)
                _content.Navigate(page);
        }
        catch (Exception ex)
        {
            StartupGuard.Write("Navigate:" + tag, ex);
            _content.Content = new ScrollViewer
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
