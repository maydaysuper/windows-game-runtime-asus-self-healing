using System.Runtime.CompilerServices;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

internal static class EarlyRuntime
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        // Before any WPF window. Win11 touch/pen init can hang the first frame.
        AppContext.SetSwitch("Switch.System.Windows.Input.Stylus.DisableStylusAndTouchSupport", true);
        StartupGuard.ApplyHostDirectory();
    }
}

public static class Program
{
    [STAThread]
    public static void Main()
    {
        StartupGuard.Install();
        if (!StartupGuard.TryBecomePrimary())
            return;
        StartupGuard.PrepareLaunch();
        try
        {
            StartupGuard.ProbeNativeRuntime();
            var app = new App();
            app.InitializeComponent();
            app.Run();
        }
        catch (Exception ex)
        {
            StartupGuard.Write("Main", ex);
            StartupGuard.Notify(ex);
        }
    }
}
