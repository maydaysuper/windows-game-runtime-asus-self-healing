using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

/// <summary>
/// Local, read-only GPU memory telemetry using Windows PDH English counters and DXGI adapter metadata.
/// It intentionally avoids vendor SDK dependencies and never allocates GPU resources itself.
/// </summary>
public sealed partial class GpuMemoryTelemetryService
{
    private const uint PdhFmtDouble = 0x00000200;
    private const int PdhMoreData = unchecked((int)0x800007D2);
    private const int DxgiErrorNotFound = unchecked((int)0x887A0002);
    private readonly AdaptiveResourceGovernor _resources;

    public GpuMemoryTelemetryService(AdaptiveResourceGovernor resources) => _resources = resources;

    public async Task<GpuMemorySnapshot> CapturePeakAsync(
        int samples = 4,
        TimeSpan? interval = null,
        CancellationToken cancellationToken = default)
    {
        samples = Math.Clamp(samples, 1, 10);
        interval ??= TimeSpan.FromMilliseconds(300);
        using var lease = await _resources.EnterBackgroundWorkAsync(cancellationToken).ConfigureAwait(false);
        return await Task.Run(async () =>
        {
            var adapters = EnumerateDxgiAdapters();
            var peaksDedicated = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var peaksShared = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var lastDedicated = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var lastShared = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var warnings = new List<string>();
            var anyCounter = false;

            using var query = new PdhGpuMemoryQuery();
            for (var i = 0; i < samples; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    var sample = query.Sample();
                    anyCounter |= sample.Available;
                    Merge(lastDedicated, peaksDedicated, sample.DedicatedByLuid);
                    Merge(lastShared, peaksShared, sample.SharedByLuid);
                    if (!string.IsNullOrWhiteSpace(sample.Warning) && !warnings.Contains(sample.Warning, StringComparer.OrdinalIgnoreCase))
                        warnings.Add(sample.Warning);
                }
                catch (Exception ex)
                {
                    if (!warnings.Contains(ex.Message, StringComparer.OrdinalIgnoreCase)) warnings.Add(ex.Message);
                }

                if (i + 1 < samples) await Task.Delay(interval.Value, cancellationToken).ConfigureAwait(false);
            }

            var rows = new List<GpuMemoryAdapterSnapshot>();
            foreach (var adapter in adapters)
            {
                rows.Add(new GpuMemoryAdapterSnapshot
                {
                    Name = adapter.Name,
                    Luid = adapter.Luid,
                    DedicatedLimitBytes = adapter.DedicatedVideoMemory,
                    DedicatedUsageBytes = FindUsage(lastDedicated, adapter.Luid),
                    DedicatedPeakBytes = FindUsage(peaksDedicated, adapter.Luid),
                    SharedUsageBytes = FindUsage(lastShared, adapter.Luid),
                    SharedPeakBytes = FindUsage(peaksShared, adapter.Luid)
                });
            }

            if (rows.Count == 0 && (lastDedicated.Count > 0 || lastShared.Count > 0))
            {
                foreach (var luid in lastDedicated.Keys.Union(lastShared.Keys, StringComparer.OrdinalIgnoreCase))
                {
                    rows.Add(new GpuMemoryAdapterSnapshot
                    {
                        Name = "Windows GPU Adapter " + luid,
                        Luid = luid,
                        DedicatedUsageBytes = FindUsage(lastDedicated, luid),
                        DedicatedPeakBytes = FindUsage(peaksDedicated, luid),
                        SharedUsageBytes = FindUsage(lastShared, luid),
                        SharedPeakBytes = FindUsage(peaksShared, luid)
                    });
                }
            }

            return new GpuMemorySnapshot(rows, anyCounter, string.Join(" | ", warnings), DateTimeOffset.UtcNow);
        }, cancellationToken).ConfigureAwait(false);
    }

    private static void Merge(Dictionary<string, long> last, Dictionary<string, long> peaks, IReadOnlyDictionary<string, long> values)
    {
        foreach (var (key, value) in values)
        {
            last[key] = Math.Max(0, value);
            peaks[key] = Math.Max(peaks.GetValueOrDefault(key), Math.Max(0, value));
        }
    }

    private static long FindUsage(IReadOnlyDictionary<string, long> values, string luid)
    {
        if (values.TryGetValue(luid, out var exact)) return exact;
        if (values.Count == 1) return values.Values.First();
        return 0;
    }

    private static IReadOnlyList<DxgiAdapterInfo> EnumerateDxgiAdapters()
    {
        var result = new List<DxgiAdapterInfo>();
        var iid = typeof(IDXGIFactory1).GUID;
        var hr = CreateDXGIFactory1(ref iid, out var factory);
        if (hr < 0 || factory is null) return result;
        try
        {
            for (uint index = 0; ; index++)
            {
                hr = factory.EnumAdapters1(index, out var adapter);
                if (hr == DxgiErrorNotFound || adapter is null) break;
                if (hr < 0) break;
                try
                {
                    adapter.GetDesc1(out var desc);
                    if ((desc.Flags & 2u) != 0) continue; // DXGI_ADAPTER_FLAG_SOFTWARE
                    result.Add(new DxgiAdapterInfo(
                        desc.Description?.TrimEnd('\0') ?? $"GPU {index}",
                        FormatLuid(desc.AdapterLuid),
                        checked((long)desc.DedicatedVideoMemory.ToUInt64())));
                }
                finally
                {
                    if (Marshal.IsComObject(adapter)) Marshal.ReleaseComObject(adapter);
                }
            }
        }
        finally
        {
            if (Marshal.IsComObject(factory)) Marshal.ReleaseComObject(factory);
        }
        return result;
    }

    private static string FormatLuid(Luid luid)
        => $"0x{unchecked((uint)luid.HighPart):X8}_0x{luid.LowPart:X8}";

    private sealed record DxgiAdapterInfo(string Name, string Luid, long DedicatedVideoMemory);

    private sealed class PdhGpuMemoryQuery : IDisposable
    {
        private IntPtr _query;
        private IntPtr _dedicated;
        private IntPtr _shared;
        private string _setupWarning = "";

        public PdhGpuMemoryQuery()
        {
            var status = PdhOpenQueryW(null, UIntPtr.Zero, out _query);
            if (status != 0) { _setupWarning = $"PDH OpenQuery=0x{status:X8}"; return; }
            var d = PdhAddEnglishCounterW(_query, @"\GPU Adapter Memory(*)\Dedicated Usage", UIntPtr.Zero, out _dedicated);
            var s = PdhAddEnglishCounterW(_query, @"\GPU Adapter Memory(*)\Shared Usage", UIntPtr.Zero, out _shared);
            if (d != 0 || s != 0) _setupWarning = $"GPU Adapter Memory counters unavailable (Dedicated=0x{d:X8}, Shared=0x{s:X8})";
            _ = PdhCollectQueryData(_query);
        }

        public CounterSample Sample()
        {
            if (_query == IntPtr.Zero || _dedicated == IntPtr.Zero || _shared == IntPtr.Zero)
                return new CounterSample(false, new Dictionary<string, long>(), new Dictionary<string, long>(), _setupWarning);

            var status = PdhCollectQueryData(_query);
            if (status != 0)
                return new CounterSample(false, new Dictionary<string, long>(), new Dictionary<string, long>(), $"PDH Collect=0x{status:X8}");

            var dedicated = ReadCounterArray(_dedicated);
            var shared = ReadCounterArray(_shared);
            return new CounterSample(true, dedicated, shared, _setupWarning);
        }

        private static Dictionary<string, long> ReadCounterArray(IntPtr counter)
        {
            uint bufferSize = 0;
            var status = PdhGetFormattedCounterArrayW(counter, PdhFmtDouble, ref bufferSize, out var itemCount, IntPtr.Zero);
            if (status != PdhMoreData || bufferSize == 0) return new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);

            var buffer = Marshal.AllocHGlobal(checked((int)bufferSize));
            try
            {
                status = PdhGetFormattedCounterArrayW(counter, PdhFmtDouble, ref bufferSize, out itemCount, buffer);
                if (status != 0 || itemCount == 0) return new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
                var result = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
                var size = Marshal.SizeOf<PdhFmtCounterValueItem>();
                for (var i = 0; i < itemCount; i++)
                {
                    var item = Marshal.PtrToStructure<PdhFmtCounterValueItem>(IntPtr.Add(buffer, checked((int)(i * (uint)size))));
                    var name = Marshal.PtrToStringUni(item.Name) ?? "";
                    if (item.Value.CStatus > 1 || double.IsNaN(item.Value.DoubleValue) || item.Value.DoubleValue < 0) continue;
                    var luid = ExtractLuid(name);
                    if (string.IsNullOrWhiteSpace(luid)) continue;
                    var bytes = item.Value.DoubleValue >= long.MaxValue ? long.MaxValue : (long)item.Value.DoubleValue;
                    result[luid] = checked(result.GetValueOrDefault(luid) + Math.Max(0, bytes));
                }
                return result;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        public void Dispose()
        {
            if (_query != IntPtr.Zero) { _ = PdhCloseQuery(_query); _query = IntPtr.Zero; }
        }
    }

    private static string ExtractLuid(string instance)
    {
        var match = LuidRegex().Match(instance);
        if (!match.Success) return "";
        return $"{match.Groups[1].Value.ToLowerInvariant()}_{match.Groups[2].Value.ToLowerInvariant()}";
    }

    [GeneratedRegex(@"luid_(0x[0-9a-fA-F]+)_(0x[0-9a-fA-F]+)", RegexOptions.CultureInvariant)]
    private static partial Regex LuidRegex();

    private sealed record CounterSample(
        bool Available,
        IReadOnlyDictionary<string, long> DedicatedByLuid,
        IReadOnlyDictionary<string, long> SharedByLuid,
        string Warning);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PdhFmtCounterValueItem
    {
        public IntPtr Name;
        public PdhFmtCounterValue Value;
    }

    [StructLayout(LayoutKind.Explicit, Size = 16)]
    private struct PdhFmtCounterValue
    {
        [FieldOffset(0)] public uint CStatus;
        [FieldOffset(8)] public double DoubleValue;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DxgiAdapterDesc1
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public Luid AdapterLuid;
        public uint Flags;
    }

    [ComImport, Guid("770AAE78-F26F-4DBA-A829-253C83D1B387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDXGIFactory1
    {
        void SetPrivateData(ref Guid name, uint dataSize, IntPtr data);
        void SetPrivateDataInterface(ref Guid name, IntPtr unknown);
        void GetPrivateData(ref Guid name, ref uint dataSize, IntPtr data);
        void GetParent(ref Guid riid, out IntPtr parent);
        [PreserveSig] int EnumAdapters(uint adapter, out IntPtr result);
        void MakeWindowAssociation(IntPtr windowHandle, uint flags);
        void GetWindowAssociation(out IntPtr windowHandle);
        void CreateSwapChain(IntPtr device, IntPtr desc, out IntPtr swapChain);
        void CreateSoftwareAdapter(IntPtr module, out IntPtr adapter);
        [PreserveSig] int EnumAdapters1(uint adapter, [MarshalAs(UnmanagedType.Interface)] out IDXGIAdapter1 result);
        [return: MarshalAs(UnmanagedType.Bool)] bool IsCurrent();
    }

    [ComImport, Guid("29038F61-3839-4626-91FD-086879011A05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDXGIAdapter1
    {
        void SetPrivateData(ref Guid name, uint dataSize, IntPtr data);
        void SetPrivateDataInterface(ref Guid name, IntPtr unknown);
        void GetPrivateData(ref Guid name, ref uint dataSize, IntPtr data);
        void GetParent(ref Guid riid, out IntPtr parent);
        [PreserveSig] int EnumOutputs(uint output, out IntPtr result);
        [PreserveSig] int GetDesc(IntPtr desc);
        [PreserveSig] int CheckInterfaceSupport(ref Guid interfaceName, out long umdVersion);
        void GetDesc1(out DxgiAdapterDesc1 desc);
    }

    [DllImport("dxgi.dll", ExactSpelling = true)]
    private static extern int CreateDXGIFactory1(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 factory);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int PdhOpenQueryW(string? dataSource, UIntPtr userData, out IntPtr query);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int PdhAddEnglishCounterW(IntPtr query, string fullCounterPath, UIntPtr userData, out IntPtr counter);

    [DllImport("pdh.dll", ExactSpelling = true)]
    private static extern int PdhCollectQueryData(IntPtr query);

    [DllImport("pdh.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int PdhGetFormattedCounterArrayW(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr itemBuffer);

    [DllImport("pdh.dll", ExactSpelling = true)]
    private static extern int PdhCloseQuery(IntPtr query);
}
