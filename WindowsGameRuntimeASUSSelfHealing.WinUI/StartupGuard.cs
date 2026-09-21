using System.Reflection;
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

    private static readonly string[] RequiredRuntimeFiles =
    [
        "wpfgfx_cor3.dll",
        "PresentationNative_cor3.dll",
        "e_sqlite3.dll"
    ];

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
        Environment.SetEnvironmentVariable("DOTNET_BUNDLE_EXTRACT_BASE_DIR", HostDirectory);
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

    public static void ProbeNativeRuntime()
    {
        ApplyHostDirectory();
        var missing = RequiredRuntimeFiles
            .Where(name => !File.Exists(Path.Combine(HostDirectory, name)))
            .ToArray();
        if (missing.Length == 0) return;

        var dllCount = 0;
        try { dllCount = Directory.GetFiles(HostDirectory, "*.dll").Length; }
        catch { }

        throw new FileNotFoundException(
            "安装目录缺少 WPF 运行库（" + string.Join("、", missing) +
            "）。dllCount=" + dllCount +
            "。不要双击本地编译/publish 目录里的孤立 EXE。请卸载全部 3.4.x 后改装 v4.1.0 Setup，从开始菜单打开。" +
            "目录: " + HostDirectory);
    }

    public static string RuntimeSnapshot()
    {
        var ver = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "?";
        return $"version={ver}\nhost={HostDirectory}\nbase={AppContext.BaseDirectory}\nprocess={Environment.ProcessPath}";
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
                .AppendLine($"hr=0x{ex.HResult:X8}")
                .AppendLine(RuntimeSnapshot())
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
            var detail = new StringBuilder();
            for (var cur = ex; cur != null; cur = cur.InnerException)
            {
                if (detail.Length > 0) detail.Append('\n');
                detail.Append(cur.GetType().Name).Append(": ").Append(cur.Message);
            }
            var body = detail.ToString();
            if (body.Length > 900) body = body[..900] + "…";
            MessageBoxW(
                IntPtr.Zero,
                "程序启动失败。\n\n" + body + "\n\n日志: " + log,
                "Windows 游戏运行环境自愈中心",
                0x00000010);
        }
        catch { }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string? text, string? caption, uint type);
}
