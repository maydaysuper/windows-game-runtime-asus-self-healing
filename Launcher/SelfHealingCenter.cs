using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private const string InnerExeName = "WindowsGameRuntimeASUSSelfHealing.WinUI.exe";
    private const uint MbIconError = 0x00000010;
    private const int AttachParentProcess = -1;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern bool AttachConsole(int dwProcessId);

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            var module = Process.GetCurrentProcess().MainModule;
            var processPath = module == null ? null : module.FileName;
            if (string.IsNullOrWhiteSpace(processPath))
            {
                Fail("无法确定启动器位置。");
                return 1;
            }

            var root = Path.GetDirectoryName(processPath);
            if (string.IsNullOrWhiteSpace(root))
            {
                Fail("无法确定程序目录。");
                return 1;
            }

            if (IsVersionRequest(args))
                return PrintVersion(processPath, root);
            if (IsDiagnosticsRequest(args))
                return PrintDiagnostics(processPath, root);

            var appDir = Path.Combine(root, "App");
            var exe = Path.Combine(appDir, InnerExeName);
            if (!File.Exists(exe))
            {
                Fail("找不到 App 目录里的主程序。\n\n请把压缩包整个解压后再双击「奥创修复中心」。不要只复制这一个 EXE，也不要从开始菜单查找。");
                return 1;
            }

            var psi = new ProcessStartInfo
            {
                FileName = exe,
                WorkingDirectory = appDir,
                UseShellExecute = true
            };
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            Fail("启动失败。\n\n" + ex.Message);
            return 1;
        }
    }

    private static bool IsVersionRequest(string[] args)
    {
        foreach (var arg in args)
        {
            if (string.Equals(arg, "--version", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "-v", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(arg, "/version", StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static int PrintVersion(string launcherPath, string root)
    {
        try { AttachConsole(AttachParentProcess); } catch { }
        var launcherVer = FileVersionInfo.GetVersionInfo(launcherPath);
        var inner = Path.Combine(root, "App", InnerExeName);
        var innerVer = File.Exists(inner) ? FileVersionInfo.GetVersionInfo(inner).FileVersion : "";
        if (string.IsNullOrWhiteSpace(innerVer) ||
            !string.Equals(innerVer, launcherVer.FileVersion, StringComparison.Ordinal))
        {
            Console.Error.WriteLine("Installed App executable is missing or has a different version.");
            return 1;
        }
        var line = "奥创修复中心 " + (launcherVer.ProductVersion ?? launcherVer.FileVersion);
        if (!string.IsNullOrWhiteSpace(innerVer))
            line += " (App " + innerVer + ")";
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine(line);
        return 0;
    }

    private static bool IsDiagnosticsRequest(string[] args)
    {
        foreach (var arg in args)
            if (string.Equals(arg, "--diagnose-install", StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    private static int PrintDiagnostics(string launcherPath, string root)
    {
        var status = PrintVersion(launcherPath, root);
        if (status != 0) return status;
        var inner = Path.Combine(root, "App", InnerExeName);
        Console.WriteLine("OS version: " + Environment.OSVersion.Version);
        Console.WriteLine("Launcher: " + launcherPath);
        Console.WriteLine("App: " + inner);
        Console.WriteLine("State: " + Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsGameRuntimeASUSSelfHealing", "State"));
        return 0;
    }

    private static void Fail(string text)
    {
        MessageBoxW(IntPtr.Zero, text, "奥创修复中心", MbIconError);
    }
}
