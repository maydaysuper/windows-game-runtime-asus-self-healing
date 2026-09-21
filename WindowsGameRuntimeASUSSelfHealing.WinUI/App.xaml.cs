using System.Windows;
using System.Windows.Threading;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class App : Application
{
    public static AppServices Services { get; } = CreateServices();

    public App()
    {
        StartupGuard.Install();
        DispatcherUnhandledException += OnDispatcherUnhandled;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            var window = new MainWindow();
            MainWindow = window;
            window.Closed += (_, _) => Services.Dispose();
            window.Show();
            _ = WarmStateStoreAsync();
        }
        catch (Exception ex)
        {
            StartupGuard.Write("OnStartup", ex);
            StartupGuard.Notify(ex);
            Shutdown(-1);
        }
    }

    private static void OnDispatcherUnhandled(object sender, DispatcherUnhandledExceptionEventArgs args)
    {
        StartupGuard.Write("DispatcherUnhandled", args.Exception);
        args.Handled = true;
        StartupGuard.Notify(args.Exception);
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
        try
        {
            await Services.StateStore.InitializeAsync().ConfigureAwait(false);
            await Services.Workflow.InitializeAsync().ConfigureAwait(false);
        }
        catch (Exception ex) { StartupGuard.Write("WarmStateStore", ex); }
    }
}
