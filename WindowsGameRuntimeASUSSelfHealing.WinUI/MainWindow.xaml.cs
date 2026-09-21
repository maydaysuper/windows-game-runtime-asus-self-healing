using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Navigation;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class MainWindow : Window
{
    private readonly Dictionary<string, Page> _pages = new(StringComparer.Ordinal);
    private readonly SolidColorBrush _navIdle = new(Color.FromRgb(255, 255, 255));
    private readonly SolidColorBrush _navActive = new(Color.FromRgb(15, 23, 42));
    private readonly SolidColorBrush _navIdleFg = new(Color.FromRgb(15, 23, 42));

    public MainWindow()
    {
        try
        {
            InitializeComponent();
        }
        catch (Exception ex)
        {
            StartupGuard.Write("MainWindow.InitializeComponent", ex);
            BuildShellInCode();
        }

        try
        {
            var build = App.Services.Backend.GetBuildIdentity();
            if (VersionText != null)
                VersionText.Text = $"WPF · v{build.Version}";
            if (BuildText != null)
                BuildText.Text = $"{build.BuildId} · {build.WindowsAppSdk} · .NET {build.DotNet} · {build.Language}";
        }
        catch (Exception ex)
        {
            StartupGuard.Write("MainWindow.Identity", ex);
            if (VersionText != null) VersionText.Text = "WPF";
        }

        NavigateTag("overview");
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string tag })
            NavigateTag(tag);
    }

    private void NavigateTag(string tag)
    {
        if (ContentFrame == null) return;
        var page = GetCachedPage(tag);
        try
        {
            if (!ReferenceEquals(ContentFrame.Content, page))
                ContentFrame.Navigate(page);
            Highlight(tag);
            if (StatusText != null)
                StatusText.Text = tag switch
                {
                    "asus" => "ASUS 奥创中心 · 未知版本只诊断不套用旧修复",
                    "runtime" => "游戏运行库 · Microsoft 官方包签名校验",
                    "crash" => "崩溃 / GPU / ReBAR / Dump · 全部本机分析",
                    "reports" => "报告中心 · 事务、验收与诊断包",
                    _ => "系统健康 · 后台任务按硬件自适应限流"
                };
            try { App.Services.SessionLog.Note("Navigate", tag); } catch { }
        }
        catch (Exception ex)
        {
            StartupGuard.Write("Navigate:" + tag, ex);
            _pages.Remove(tag);
            try
            {
                var fresh = CreatePage(tag);
                _pages[tag] = fresh;
                ContentFrame.Navigate(fresh);
                Highlight(tag);
            }
            catch (Exception inner)
            {
                StartupGuard.Write("NavigateRetry:" + tag, inner);
                ContentFrame.Content = new TextBox
                {
                    Text = "页面加载失败（" + tag + "）\n\n" + inner,
                    IsReadOnly = true,
                    TextWrapping = TextWrapping.Wrap,
                    BorderThickness = new Thickness(0),
                    Padding = new Thickness(24)
                };
            }
        }
    }

    private Page GetCachedPage(string tag)
    {
        if (_pages.TryGetValue(tag, out var existing) && existing is not null)
            return existing;
        var page = CreatePage(tag);
        _pages[tag] = page;
        return page;
    }

    private static Page CreatePage(string tag) => tag switch
    {
        "overview" => new OverviewPage(),
        "asus" => new SafetyPage(),
        "runtime" => new RuntimePage(),
        "crash" => new CrashPage(),
        "reports" => new ReportsPage(),
        _ => new OverviewPage()
    };

    private void Highlight(string tag)
    {
        foreach (var btn in NavButtons())
        {
            var on = string.Equals(btn.Tag as string, tag, StringComparison.Ordinal);
            btn.Background = on ? _navActive : _navIdle;
            btn.Foreground = on ? Brushes.White : _navIdleFg;
        }
    }

    private IEnumerable<Button> NavButtons()
    {
        if (OverviewNav != null) yield return OverviewNav;
        if (AsusNav != null) yield return AsusNav;
        if (RuntimeNav != null) yield return RuntimeNav;
        if (CrashNav != null) yield return CrashNav;
        if (ReportsNav != null) yield return ReportsNav;
    }

    private void BuildShellInCode()
    {
        var root = new Grid { Background = new SolidColorBrush(Color.FromRgb(248, 250, 252)) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = new Border { Padding = new Thickness(16, 12, 16, 12), Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)) };
        var headerDock = new DockPanel();
        headerDock.Children.Add(new TextBlock
        {
            Text = "Windows 游戏运行环境自愈中心",
            Foreground = Brushes.White,
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        });
        VersionText = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(147, 197, 253)), FontSize = 12, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(VersionText, Dock.Right);
        headerDock.Children.Insert(0, VersionText);
        header.Child = headerDock;
        Grid.SetRow(header, 0);

        NavBar = new StackPanel { Orientation = Orientation.Horizontal, Background = new SolidColorBrush(Color.FromRgb(226, 232, 240)), Height = 48 };
        OverviewNav = MakeNav("系统健康", "overview");
        AsusNav = MakeNav("ASUS 奥创中心", "asus");
        RuntimeNav = MakeNav("游戏运行库", "runtime");
        CrashNav = MakeNav("崩溃 / Dump", "crash");
        ReportsNav = MakeNav("报告中心", "reports");
        OverviewNav.Margin = new Thickness(12, 8, 0, 8);
        NavBar.Children.Add(OverviewNav);
        NavBar.Children.Add(AsusNav);
        NavBar.Children.Add(RuntimeNav);
        NavBar.Children.Add(CrashNav);
        NavBar.Children.Add(ReportsNav);
        Grid.SetRow(NavBar, 1);

        ContentFrame = new Frame { NavigationUIVisibility = NavigationUIVisibility.Hidden, JournalOwnership = JournalOwnership.OwnsJournal };
        Grid.SetRow(ContentFrame, 2);

        var footer = new Border { Padding = new Thickness(14, 8, 14, 8), BorderBrush = new SolidColorBrush(Color.FromRgb(226, 232, 240)), BorderThickness = new Thickness(0, 1, 0, 0), Background = Brushes.White };
        var footerDock = new DockPanel();
        StatusText = new TextBlock { Text = "就绪 · 后台任务按硬件自适应限流", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)) };
        BuildText = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), HorizontalAlignment = HorizontalAlignment.Right };
        DockPanel.SetDock(BuildText, Dock.Right);
        footerDock.Children.Add(BuildText);
        footerDock.Children.Add(StatusText);
        footer.Child = footerDock;
        Grid.SetRow(footer, 3);

        root.Children.Add(header);
        root.Children.Add(NavBar);
        root.Children.Add(ContentFrame);
        root.Children.Add(footer);
        Content = root;
        Background = new SolidColorBrush(Color.FromRgb(248, 250, 252));
        Title = "Windows 游戏运行环境自愈中心";
        Width = 1360;
        Height = 860;
        MinWidth = 960;
        MinHeight = 640;
    }

    private Button MakeNav(string content, string tag)
    {
        var btn = new Button { Content = content, Tag = tag, Margin = new Thickness(4, 8, 0, 8) };
        btn.Click += Nav_Click;
        return btn;
    }
}
