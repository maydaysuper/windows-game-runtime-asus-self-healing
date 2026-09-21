using System.Runtime.CompilerServices;
using System.Windows;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

internal static class EarlyRuntime
{
    [ModuleInitializer]
    internal static void Initialize() => StartupGuard.ApplyHostDirectory();
}

public static class Program
{
    [STAThread]
    public static void Main()
    {
        StartupGuard.Install();
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
