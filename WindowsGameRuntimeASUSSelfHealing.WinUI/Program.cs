using System.Runtime.CompilerServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using WinRT;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

internal static class EarlyRuntime
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        StartupGuard.ApplyHostDirectory();
    }
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
            ComWrappersSupport.InitializeComWrappers();
            Application.Start(p =>
            {
                var context = new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                new App();
            });
        }
        catch (Exception ex)
        {
            StartupGuard.Write("Main", ex);
            StartupGuard.Notify(ex);
        }
    }
}
