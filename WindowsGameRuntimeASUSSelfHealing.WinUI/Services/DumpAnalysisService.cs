using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class DumpAnalysisService
{
    private const uint ModuleListStream = 4;
    private const uint ExceptionStream = 6;
    private const int MinidumpModuleSize = 108;
    private readonly AdaptiveResourceGovernor _resources;

    public DumpAnalysisService(AdaptiveResourceGovernor resources) => _resources = resources;

    public async Task<DumpAnalysisResult> AnalyzeAsync(string path, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            throw new FileNotFoundException("Dump 文件不存在。", path);
        if (!Path.GetExtension(path).Equals(".dmp", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("只支持 Windows .dmp / minidump 文件。\n");

        using var lease = await _resources.EnterBackgroundWorkAsync(cancellationToken).ConfigureAwait(false);
        return await Task.Run(() => AnalyzeCore(path, cancellationToken), cancellationToken).ConfigureAwait(false);
    }

    private static DumpAnalysisResult AnalyzeCore(string path, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var info = new FileInfo(path);
        if (info.Length < 32) throw new InvalidDataException("Dump 文件过小或已损坏。");

        using var mapped = MemoryMappedFile.CreateFromFile(path, FileMode.Open, null, 0, MemoryMappedFileAccess.Read);
        using var view = mapped.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read);
        var handle = view.SafeMemoryMappedViewHandle;
        var added = false;
        try
        {
            handle.DangerousAddRef(ref added);
            var basePointer = Add(handle.DangerousGetHandle(), view.PointerOffset);
            if (ReadUInt32(basePointer, 0) != 0x504D444D)
                throw new InvalidDataException("文件不是有效的 Windows Minidump（MDMP signature 不匹配）。");

            if (!MiniDumpReadDumpStream(basePointer, ExceptionStream, out _, out var exceptionPtr, out var exceptionSize) ||
                exceptionPtr == IntPtr.Zero || exceptionSize < 40)
            {
                return new DumpAnalysisResult
                {
                    FileName = info.Name,
                    FilePath = path,
                    FileSizeBytes = info.Length,
                    Category = "NO_EXCEPTION_STREAM",
                    Confidence = "LOW",
                    CoreReason = "Dump 中没有异常流。它可能是手工抓取、挂起状态 Dump，或采集时未包含异常上下文。",
                    Evidence = "MINIDUMP_EXCEPTION_STREAM not present",
                    AnalyzedUtc = DateTimeOffset.UtcNow
                };
            }

            cancellationToken.ThrowIfCancellationRequested();
            var code = ReadUInt32(exceptionPtr, 8);
            var address = ReadUInt64(exceptionPtr, 24);
            var exceptionName = ExceptionName(code);
            var modules = ReadModules(basePointer, info.Length);
            var faultingModule = modules.FirstOrDefault(x => address >= x.Base && address < x.Base + x.Size)?.Name ?? "未能映射到模块";
            var diagnosis = Diagnose(code, faultingModule);

            var evidence = new StringBuilder();
            evidence.Append($"Exception={FormatCode(code)} ({exceptionName}); Address=0x{address:X16}");
            if (!string.IsNullOrWhiteSpace(faultingModule)) evidence.Append($"; FaultingModule={faultingModule}");
            evidence.Append($"; ModulesInDump={modules.Count}");

            return new DumpAnalysisResult
            {
                FileName = info.Name,
                FilePath = path,
                FileSizeBytes = info.Length,
                ExceptionCode = FormatCode(code),
                ExceptionName = exceptionName,
                ExceptionAddress = $"0x{address:X16}",
                FaultingModule = faultingModule,
                Category = diagnosis.Category,
                Confidence = diagnosis.Confidence,
                CoreReason = diagnosis.Reason,
                Evidence = evidence.ToString(),
                AnalyzedUtc = DateTimeOffset.UtcNow
            };
        }
        finally
        {
            if (added) handle.DangerousRelease();
        }
    }

    private static List<DumpModule> ReadModules(IntPtr basePointer, long fileLength)
    {
        var result = new List<DumpModule>();
        if (!MiniDumpReadDumpStream(basePointer, ModuleListStream, out _, out var modulesPtr, out var streamSize) ||
            modulesPtr == IntPtr.Zero || streamSize < 4)
            return result;

        var declared = ReadUInt32(modulesPtr, 0);
        var maxByStream = (streamSize - 4) / MinidumpModuleSize;
        var count = (int)Math.Min(Math.Min(declared, maxByStream), 4096u);
        for (var i = 0; i < count; i++)
        {
            var offset = 4 + i * MinidumpModuleSize;
            var moduleBase = ReadUInt64(modulesPtr, offset);
            var imageSize = ReadUInt32(modulesPtr, offset + 8);
            var nameRva = ReadUInt32(modulesPtr, offset + 20);
            var name = ReadMinidumpString(basePointer, nameRva, fileLength);
            if (string.IsNullOrWhiteSpace(name)) name = $"module_{i}";
            try { name = Path.GetFileName(name); } catch { }
            result.Add(new DumpModule(name, moduleBase, imageSize));
        }
        return result;
    }

    private static string ReadMinidumpString(IntPtr basePointer, uint rva, long fileLength)
    {
        if (rva == 0 || rva + 4L > fileLength) return "";
        var pointer = Add(basePointer, rva);
        var byteLength = ReadUInt32(pointer, 0);
        if (byteLength == 0 || byteLength > 16 * 1024 || rva + 4L + byteLength > fileLength) return "";
        var bytes = new byte[(int)byteLength];
        Marshal.Copy(Add(pointer, 4), bytes, 0, bytes.Length);
        return Encoding.Unicode.GetString(bytes).TrimEnd('\0');
    }

    private static Diagnosis Diagnose(uint code, string module)
    {
        var name = module.ToLowerInvariant();
        var isSystemEndpoint = name is "ntdll.dll" or "kernelbase.dll" or "kernel32.dll";
        if (ContainsAny(name, "nvwgf2umx", "nvlddmkm", "amdxx", "atidxx", "aticfx", "igd10iumd", "igd12umd", "igc64"))
            return new("GPU_DRIVER", "HIGH", $"异常指令落在显卡驱动模块 {module}。核心方向是 GPU 用户态驱动/图形调用链；应继续核对驱动版本、GPU 超时事件和同时间段 WER/GPU 事件，而不是自动 DDU。");
        if (ContainsAny(name, "rtsshooks", "nahimic", "discordhook", "gameoverlayrenderer", "nvspcap", "gamebar", "obs"))
            return new("OVERLAY_INJECTION", "HIGH", $"异常指令落在覆盖层/注入模块 {module}。优先怀疑 Overlay、监控、音效或录屏 Hook 与游戏渲染链冲突。");
        if (ContainsAny(name, "d3d11", "d3d12", "dxgi"))
            return new("GRAPHICS_API", "MEDIUM", $"异常落点在 {module} 图形 API 链。它说明崩溃发生在渲染路径，但 Microsoft 图形 DLL 往往不是最终根因；需结合 GPU 驱动事件和游戏自身模块继续判断。");
        if (ContainsAny(name, "vcruntime", "msvcp", "ucrtbase"))
            return new("CPP_RUNTIME", "MEDIUM", $"异常落点在 C/C++ 运行库 {module}。常见于程序自身内存状态异常，也可能与运行库损坏有关；本软件会将其与 VC++ 完整性检测交叉判断，不能仅凭 DLL 名断定是运行库本身损坏。");
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            return new("APPLICATION", "MEDIUM", $"异常指令直接落在主程序 {module}。当前证据更偏向游戏/应用自身代码路径、Mod/插件状态或其输入数据；建议结合异常码和最近更新继续排查。");
        if (isSystemEndpoint)
            return new("SYSTEM_EXCEPTION_ENDPOINT", "LOW", $"异常最终落在系统异常处理模块 {module}。这类模块经常只是抛出/终止位置，不足以单独认定 Windows 本身是根因；需要调用栈或相邻事件进一步确认。");

        var exceptionReason = code switch
        {
            0xC0000005 => "访问冲突：程序读/写/执行了无效内存地址。",
            0xC0000374 => "堆损坏：检测到 heap 元数据被破坏，常见于越界写、释放后使用或第三方注入冲突。",
            0xC0000409 => "快速失败/栈缓冲区安全检查触发，通常表示进程检测到不可继续的内存安全状态。",
            0xC00000FD => "栈溢出：递归或异常调用深度耗尽线程栈。",
            0xC000001D => "非法指令：CPU 执行了无效/不受支持的指令。",
            0xC0000094 => "整数除零异常。",
            0xE06D7363 => "Microsoft C++ 异常未被进程正常处理。",
            0xE0434352 => ".NET CLR 异常未被进程正常处理。",
            _ => $"异常 {FormatCode(code)} 在进程中未被处理。"
        };
        var moduleText = string.IsNullOrWhiteSpace(module) || module == "未能映射到模块" ? "未能确定故障模块" : $"故障指令位于 {module}";
        return new("UNHANDLED_EXCEPTION", "MEDIUM", $"{exceptionReason} {moduleText}。这是核心报错点；若要确认最终根因仍需符号化调用栈。" );
    }

    private static bool ContainsAny(string text, params string[] values)
        => values.Any(v => text.Contains(v, StringComparison.Ordinal));

    private static string ExceptionName(uint code) => code switch
    {
        0xC0000005 => "Access Violation",
        0xC0000374 => "Heap Corruption",
        0xC0000409 => "Stack Buffer Overrun / Fast Fail",
        0xC00000FD => "Stack Overflow",
        0xC000001D => "Illegal Instruction",
        0xC0000094 => "Integer Divide By Zero",
        0x80000003 => "Breakpoint",
        0xE06D7363 => "Microsoft C++ Exception",
        0xE0434352 => ".NET CLR Exception",
        _ => "Unhandled Exception"
    };

    private static string FormatCode(uint code) => $"0x{code:X8}";
    private static IntPtr Add(IntPtr pointer, long offset) => new(pointer.ToInt64() + offset);
    private static uint ReadUInt32(IntPtr pointer, int offset) => unchecked((uint)Marshal.ReadInt32(pointer, offset));
    private static ulong ReadUInt64(IntPtr pointer, int offset) => unchecked((ulong)Marshal.ReadInt64(pointer, offset));

    [DllImport("dbghelp.dll", EntryPoint = "MiniDumpReadDumpStream", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MiniDumpReadDumpStream(
        IntPtr BaseOfDump,
        uint StreamNumber,
        out IntPtr Dir,
        out IntPtr StreamPointer,
        out uint StreamSize);

    private sealed record DumpModule(string Name, ulong Base, uint Size);
    private sealed record Diagnosis(string Category, string Confidence, string Reason);
}
