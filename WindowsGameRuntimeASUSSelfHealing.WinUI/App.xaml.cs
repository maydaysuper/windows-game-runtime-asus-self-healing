using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class App : Application
{
    private Window? _window;
    public Window? MainWindow => _window;
    public static AppServices Services { get; } = CreateServices();

    public App()
    {
        StartupGuard.Install();
        InitializeComponent();
        EnsureWinUiResources();
        UnhandledException += (_, args) =>
        {
            StartupGuard.Write("XamlUnhandledException", args.Exception);
            args.Handled = true;
            System.Diagnostics.Debug.WriteLine(args.Exception);
        };
    }

    private static void EnsureWinUiResources()
    {
        try
        {
            if (Current.Resources.MergedDictionaries.OfType<XamlControlsResources>().Any()) return;
            Current.Resources.MergedDictionaries.Insert(0, new XamlControlsResources());
        }
        catch (Exception ex) { StartupGuard.Write("XamlControlsResources", ex); }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Closed += (_, _) => Services.Dispose();
            _window.Activate();
            _ = WarmStateStoreAsync();
        }
        catch (Exception ex)
        {
            StartupGuard.Write("OnLaunched", ex);
            try
            {
                var fallback = new Window { Title = "Windows 游戏运行环境自愈中心" };
                fallback.Content = new ScrollViewer
                {
                    Content = new TextBlock
                    {
                        Text = "主窗口启动失败，已进入诊断模式。\n请卸载后改装 v3.4.13。\n\n" + ex + "\n\n" + StartupGuard.RuntimeSnapshot(),
                        TextWrapping = TextWrapping.Wrap,
                        Margin = new Thickness(24),
                        IsTextSelectionEnabled = true
                    }
                };
                fallback.Activate();
                _window = fallback;
            }
            catch
            {
                StartupGuard.Notify(ex);
                throw;
            }
        }
    }

    private static AppServices CreateServices()
    {
        try { return new AppServices(); }
        catch (Exception ex)
        {
            StartupGuard.Write("AppServices", ex);
            throw;
        }
    }

    private static async Task WarmStateStoreAsync()
    {
        try {
            await Services.StateStore.InitializeAsync().ConfigureAwait(false);
            await Services.Workflow.InitializeAsync().ConfigureAwait(false);
        }
        catch (Exception ex) { StartupGuard.Write("WarmStateStore", ex); }
    }
}
