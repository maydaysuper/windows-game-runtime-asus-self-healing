using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class MainWindow : Window
{
    private readonly Dictionary<string, Page> _pages = new(StringComparer.Ordinal);
    private readonly SolidColorBrush _navIdle = new(Color.FromArgb(0, 0, 0, 0));
    private readonly SolidColorBrush _navActive = Brushes.White;
    private readonly SolidColorBrush _navIdleFg = new(Color.FromRgb(226, 232, 240));
    private readonly SolidColorBrush _navActiveFg = new(Color.FromRgb(15, 23, 42));

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
                VersionText.Text = $"v{build.Version}";
            if (BuildText != null)
                BuildText.Text = "";
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
            App.Services.SessionLog.Note("Navigate", tag);
            if (StatusText != null)
                StatusText.Text = tag switch
                {
                    "asus" => "奥创中心 · 只看现在有没有更新错误",
                    "runtime" => "游戏运行库 · 看能不能玩游戏",
                    "crash" => "游戏崩溃 · 看为什么崩",
                    "reports" => "报告中心 · 检测结果和修复记录",
                    _ => "系统健康 · 一眼看懂现在正不正常"
                };
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
            btn.Foreground = on ? _navActiveFg : _navIdleFg;
            btn.BorderBrush = Brushes.Transparent;
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
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var header = new Border { Padding = new Thickness(14, 10, 14, 10), Background = new SolidColorBrush(Color.FromRgb(15, 23, 42)) };
        var headerDock = new DockPanel();
        var title = new TextBlock
        {
            Text = "自愈中心",
            Foreground = Brushes.White,
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 18, 0)
        };
        VersionText = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(147, 197, 253)), FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
        DockPanel.SetDock(VersionText, Dock.Right);
        headerDock.Children.Add(VersionText);
        headerDock.Children.Add(title);
        NavBar = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        OverviewNav = MakeNav("系统健康", "overview");
        AsusNav = MakeNav("ASUS 奥创中心", "asus");
        RuntimeNav = MakeNav("游戏运行库", "runtime");
        CrashNav = MakeNav("崩溃 / Dump", "crash");
        ReportsNav = MakeNav("报告中心", "reports");
        NavBar.Children.Add(OverviewNav);
        NavBar.Children.Add(AsusNav);
        NavBar.Children.Add(RuntimeNav);
        NavBar.Children.Add(CrashNav);
        NavBar.Children.Add(ReportsNav);
        headerDock.Children.Add(NavBar);
        header.Child = headerDock;
        Grid.SetRow(header, 0);

        ContentFrame = new Frame { NavigationUIVisibility = NavigationUIVisibility.Hidden, JournalOwnership = JournalOwnership.OwnsJournal };
        Grid.SetRow(ContentFrame, 1);

        var footer = new Border { Padding = new Thickness(16, 8, 16, 8), BorderBrush = new SolidColorBrush(Color.FromRgb(226, 232, 240)), BorderThickness = new Thickness(0, 1, 0, 0), Background = Brushes.White };
        var footerDock = new DockPanel();
        StatusText = new TextBlock { Text = "就绪 · 后台任务按硬件自适应限流", Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), FontSize = 12 };
        BuildText = new TextBlock { Foreground = new SolidColorBrush(Color.FromRgb(100, 116, 139)), HorizontalAlignment = HorizontalAlignment.Right, FontSize = 12 };
        DockPanel.SetDock(BuildText, Dock.Right);
        footerDock.Children.Add(BuildText);
        footerDock.Children.Add(StatusText);
        footer.Child = footerDock;
        Grid.SetRow(footer, 2);

        root.Children.Add(header);
        root.Children.Add(ContentFrame);
        root.Children.Add(footer);
        Content = root;
        Background = new SolidColorBrush(Color.FromRgb(248, 250, 252));
        Title = "自愈中心";
        Width = 1360;
        Height = 860;
        MinWidth = 960;
        MinHeight = 640;
        TrySetIcon();
    }

    private void TrySetIcon()
    {
        try
        {
            Icon = BitmapFrame.Create(new Uri("pack://application:,,,/Assets/app.ico"));
        }
        catch { }
    }

    private Button MakeNav(string content, string tag)
    {
        var btn = new Button
        {
            Content = content,
            Tag = tag,
            Margin = new Thickness(0, 0, 6, 0),
            MinHeight = 34,
            Padding = new Thickness(14, 7, 14, 7),
            Background = _navIdle,
            Foreground = _navIdleFg,
            BorderThickness = new Thickness(0)
        };
        btn.Click += Nav_Click;
        return btn;
    }
}
