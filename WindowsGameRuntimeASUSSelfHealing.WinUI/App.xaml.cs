using Microsoft.UI.Xaml;

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
        UnhandledException += (_, args) =>
        {
            StartupGuard.Write("XamlUnhandledException", args.Exception);
            System.Diagnostics.Debug.WriteLine(args.Exception);
        };
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
            StartupGuard.Notify(ex);
            throw;
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
