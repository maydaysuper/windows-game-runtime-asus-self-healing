using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

public partial class App : Application
{
    public static AppServices Services { get; } = CreateServices();

    public App()
    {
        StartupGuard.Install();
        EventManager.RegisterClassHandler(typeof(ListView), UIElement.PreviewMouseWheelEvent, new MouseWheelEventHandler(BubbleNestedWheel), true);
        DispatcherUnhandledException += OnDispatcherUnhandled;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        try
        {
            var window = new MainWindow();
            MainWindow = window;
            window.Closed += (_, _) =>
            {
                try { Services.SessionLog.Note("SESSION_END", "main window closed"); }
                catch { }
                Services.Dispose();
            };
            window.Show();
            _ = WarmStateStoreAsync();
        }
        catch (Exception ex)
        {
            StartupGuard.Write("OnStartup", ex);
            try { Services.SessionLog.Bug("OnStartup", ex); } catch { }
            StartupGuard.Notify(ex);
            Shutdown(-1);
        }
    }

    private static void BubbleNestedWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled || sender is not DependencyObject origin) return;
        var inner = FindScrollViewer(origin);
        if (inner != null && inner.ScrollableHeight > 0)
        {
            var scrollingUp = e.Delta > 0 && inner.VerticalOffset > 0;
            var scrollingDown = e.Delta < 0 && inner.VerticalOffset < inner.ScrollableHeight;
            if (scrollingUp || scrollingDown) return;
        }

        DependencyObject? node = VisualTreeHelper.GetParent(origin);
        while (node != null && node is not ScrollViewer)
            node = VisualTreeHelper.GetParent(node);
        if (node is not ScrollViewer page) return;
        e.Handled = true;
        page.ScrollToVerticalOffset(page.VerticalOffset - e.Delta);
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject origin)
    {
        if (origin is ScrollViewer self) return self;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(origin); i++)
        {
            var found = FindScrollViewer(VisualTreeHelper.GetChild(origin, i));
            if (found != null) return found;
        }
        return null;
    }

    private static void OnDispatcherUnhandled(object sender, DispatcherUnhandledExceptionEventArgs args)
    {
        StartupGuard.Write("DispatcherUnhandled", args.Exception);
        try { Services.SessionLog.Bug("DispatcherUnhandled", args.Exception); } catch { }
        args.Handled = true;
        if (!StartupGuard.WindowReady)
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
            Services.SessionLog.Note("WarmStateStore", "ok");
        }
        catch (Exception ex)
        {
            StartupGuard.Write("WarmStateStore", ex);
            try { Services.SessionLog.Bug("WarmStateStore", ex); } catch { }
        }
    }
}
