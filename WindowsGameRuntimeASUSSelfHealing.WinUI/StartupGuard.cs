using System.Runtime.InteropServices;
using System.Text;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI;

internal static class StartupGuard
{
    public static string HostDirectory { get; private set; } = AppContext.BaseDirectory;

    public static string LogDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "WindowsGameRuntimeASUSSelfHealing",
        "Logs");

    public static void ApplyHostDirectory()
    {
        var process = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(process))
        {
            var dir = Path.GetDirectoryName(process);
            if (!string.IsNullOrWhiteSpace(dir) && Directory.Exists(dir))
                HostDirectory = dir;
        }
        else if (!string.IsNullOrWhiteSpace(AppContext.BaseDirectory))
        {
            HostDirectory = AppContext.BaseDirectory;
        }

        try { Directory.SetCurrentDirectory(HostDirectory); }
        catch { }
        Environment.SetEnvironmentVariable("MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY", HostDirectory);
    }

    public static void Install()
    {
        ApplyHostDirectory();
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            var ex = args.ExceptionObject as Exception ?? new InvalidOperationException(Convert.ToString(args.ExceptionObject));
            Write("UnhandledException", ex);
            Notify(ex);
        };
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Write("UnobservedTaskException", args.Exception);
            args.SetObserved();
        };
    }

    public static void Write(string source, Exception ex)
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            var path = Path.Combine(LogDirectory, "startup-crash.log");
            var text = new StringBuilder()
                .AppendLine($"utc={DateTimeOffset.UtcNow:o}")
                .AppendLine($"source={source}")
                .AppendLine($"host={HostDirectory}")
                .AppendLine($"base={AppContext.BaseDirectory}")
                .AppendLine($"process={Environment.ProcessPath}")
                .AppendLine(ex.ToString())
                .AppendLine()
                .ToString();
            File.AppendAllText(path, text, Encoding.UTF8);
        }
        catch { }
    }

    public static void Notify(Exception ex)
    {
        try
        {
            var log = Path.Combine(LogDirectory, "startup-crash.log");
            MessageBoxW(
                IntPtr.Zero,
                "程序启动失败。\n\n" + ex.GetType().Name + ": " + ex.Message + "\n\n日志: " + log,
                "Windows 游戏运行环境自愈中心",
                0x00000010);
        }
        catch { }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string? text, string? caption, uint type);
}
