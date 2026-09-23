using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

// IShellLinkW avoids WScript.Shell's ANSI target-path conversions on non-Chinese Windows.
public static class WgrShortcut
{
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, IntPtr findData, uint flags);
        void GetIDList(out IntPtr pidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int count);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string path);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder args, int count);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
        void GetHotkey(out short hotkey);
        void SetHotkey(short hotkey);
        void GetShowCmd(out int command);
        void SetShowCmd(int command);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int count, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }

    public sealed class Info
    {
        public string TargetPath;
        public string Arguments;
        public string WorkingDirectory;
    }

    public static Info Read(string path)
    {
        object instance = new ShellLink();
        try
        {
            ((IPersistFile)instance).Load(path, 0);
            var link = (IShellLinkW)instance;
            var target = new StringBuilder(32768);
            var args = new StringBuilder(32768);
            var working = new StringBuilder(32768);
            // SLGP_RAWPATH; never Resolve(), launch, or search for a missing target.
            link.GetPath(target, target.Capacity, IntPtr.Zero, 4);
            link.GetArguments(args, args.Capacity);
            link.GetWorkingDirectory(working, working.Capacity);
            return new Info { TargetPath = target.ToString(), Arguments = args.ToString(), WorkingDirectory = working.ToString() };
        }
        finally { Marshal.FinalReleaseComObject(instance); }
    }

    public static void Retarget(string path, string target)
    {
        object instance = new ShellLink();
        try
        {
            var file = (IPersistFile)instance;
            if (File.Exists(path)) file.Load(path, 0);
            var link = (IShellLinkW)instance;
            link.SetPath(target);
            link.SetArguments("");
            link.SetWorkingDirectory(Path.GetDirectoryName(target));
            link.SetIconLocation(target, 0);
            file.Save(path, true);
        }
        finally { Marshal.FinalReleaseComObject(instance); }
    }
}
