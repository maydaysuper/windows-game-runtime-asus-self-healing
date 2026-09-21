using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

internal static class Program
{
    private const string InnerExeName = "WindowsGameRuntimeASUSSelfHealing.WinUI.exe";
    private const uint MbIconError = 0x00000010;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    [STAThread]
    private static int Main()
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

    private static void Fail(string text)
    {
        MessageBoxW(IntPtr.Zero, text, "奥创修复中心", MbIconError);
    }
}
