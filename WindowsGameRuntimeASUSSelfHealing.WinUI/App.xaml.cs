using Microsoft.UI.Xaml;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class App : Application
{
    private Window? _window;
    public Window? MainWindow => _window;
    public static AppServices Services { get; } = new();

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, args) =>
        {
            // Log unexpected UI exceptions without marking them handled. Backend repair safety does not
            // depend on the GUI process and remains protected by Broker + Eligibility gates.
            System.Diagnostics.Debug.WriteLine(args.Exception);
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Closed += (_, _) => Services.Dispose();
        _window.Activate();
        _ = WarmStateStoreAsync();
    }

    private static async Task WarmStateStoreAsync()
    {
        try {
            await Services.StateStore.InitializeAsync().ConfigureAwait(false);
            await Services.Workflow.InitializeAsync().ConfigureAwait(false);
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine(ex); }
    }
}
