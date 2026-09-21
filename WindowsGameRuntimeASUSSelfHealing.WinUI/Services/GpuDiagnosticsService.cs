using System.Text.Json;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class GpuDiagnosticsService : IDisposable
{
    private readonly IBackendClient _backend;
    private readonly IStateStore _stateStore;
    private readonly GpuMemoryTelemetryService _memory;
    private readonly DumpAnalysisService _dumpAnalysis;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public GpuDiagnosticsService(IBackendClient backend, IStateStore stateStore, GpuMemoryTelemetryService memory, DumpAnalysisService dumpAnalysis)
    {
        _backend = backend;
        _stateStore = stateStore;
        _memory = memory;
        _dumpAnalysis = dumpAnalysis;
    }

    public async Task<GpuDiagnosisSnapshot> AnalyzeAsync(CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var since = DateTimeOffset.UtcNow.AddDays(-7).ToString("O");
            var evidenceTask = _backend.RunAsync(
                "GPU_DIAGNOSTICS",
                sinceUtc: since,
                timeout: TimeSpan.FromSeconds(75),
                cancellationToken: cancellationToken);
            var memoryTask = _memory.CapturePeakAsync(5, TimeSpan.FromMilliseconds(300), cancellationToken);
            var dumpTask = _stateStore.ReadDumpAnalysesAsync(8, cancellationToken);

            using var evidenceResult = await evidenceTask.ConfigureAwait(false);
            var memory = await memoryTask.ConfigureAwait(false);
            var dumps = (await dumpTask.ConfigureAwait(false)).ToList();
            if (!evidenceResult.Success) throw new InvalidOperationException(evidenceResult.Error);

            // Best-effort: analyze the newest Windows LiveKernelReports minidump automatically.
            // This remains local/read-only and is bounded to one dump per diagnosis run.
            var liveKernelPath = evidenceResult.Payload.Array("LiveKernelReports")
                .Select(x => x.String("Path"))
                .FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path));
            if (!string.IsNullOrWhiteSpace(liveKernelPath) &&
                !dumps.Any(x => string.Equals(x.FilePath, liveKernelPath, StringComparison.OrdinalIgnoreCase)))
            {
                try
                {
                    var liveAnalysis = await _dumpAnalysis.AnalyzeAsync(liveKernelPath, cancellationToken).ConfigureAwait(false);
                    dumps.Insert(0, liveAnalysis);
                    await _stateStore.SaveDumpAnalysisAsync(liveAnalysis, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) { throw; }
                catch { /* Event/dump evidence remains usable even when the kernel dump is locked or unsupported. */ }
            }

            return Classify(evidenceResult.Payload, memory, dumps);
        }
        finally { _gate.Release(); }
    }

    private static GpuDiagnosisSnapshot Classify(
        JsonElement payload,
        GpuMemorySnapshot memory,
        IReadOnlyList<DumpAnalysisResult> dumps)
    {
        var adapters = payload.Array("Adapters").ToArray();
        var eventSummary = payload.TryGetProperty("Events", out var e) && e.ValueKind == JsonValueKind.Object ? e : default;
        var primaryMemory = memory.PrimaryAdapter;
        var latestDump = dumps.OrderByDescending(x => x.AnalyzedUtc).FirstOrDefault();

        var displayTdr = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("DisplayTdrCount") : 0;
        var nvidia = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("NvidiaDriverEventCount") : 0;
        var amd = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("AmdDriverEventCount") : 0;
        var intel = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("IntelDriverEventCount") : 0;
        var liveKernel = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("LiveKernelGpuCount") : 0;
        var wheaPcie = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("WheaPcieCount") : 0;
        var wheaFatal = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("WheaFatalCount") : 0;
        var abrupt = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("AbruptPowerLossLikeCount") : 0;
        var kernelPower = eventSummary.ValueKind == JsonValueKind.Object ? eventSummary.Int("KernelPower41Count") : 0;
        var vendorDriver = nvidia + amd + intel;
        var tdrEvidence = displayTdr + vendorDriver + liveKernel;
        var displayTimes = ParseTimes(eventSummary, "DisplayTdrTimesUtc");
        var vendorTimes = ParseTimes(eventSummary, "VendorDriverTimesUtc");
        var liveKernelTimes = ParseTimes(eventSummary, "LiveKernelTimesUtc");
        var wheaPcieTimes = ParseTimes(eventSummary, "WheaPcieTimesUtc");
        var abruptTimes = ParseTimes(eventSummary, "AbruptPowerLossTimesUtc");
        var gpuFaultTimes = displayTimes.Concat(vendorTimes).Concat(liveKernelTimes).Distinct().OrderBy(x => x).ToArray();
        var pcieCorrelations = CountNearPairs(gpuFaultTimes, wheaPcieTimes, TimeSpan.FromMinutes(10));
        var powerCorrelations = CountNearPairs(gpuFaultTimes.Concat(wheaPcieTimes), abruptTimes, TimeSpan.FromMinutes(30));

        var rebarRows = adapters.Where(x => x.String("RebarState").Equals("LIKELY_ENABLED", StringComparison.OrdinalIgnoreCase)).ToArray();
        var rebarEnabled = rebarRows.Length > 0;
        var rebarStatus = rebarEnabled ? "LIKELY_ENABLED" : adapters.Any(x => x.String("RebarState").Equals("LIKELY_DISABLED", StringComparison.OrdinalIgnoreCase)) ? "LIKELY_DISABLED" : "UNKNOWN";
        var rebarEvidence = adapters.Length == 0
            ? "未枚举到 GPU ReBAR 证据。"
            : string.Join(" | ", adapters.Select(x => $"{x.String("Name")}: {x.String("RebarState")} / {x.String("RebarEvidence")}"));

        var dedicatedPressure = primaryMemory?.DedicatedPressurePercent ?? 0;
        var dedicatedLimit = primaryMemory?.DedicatedLimitBytes ?? 0;
        var sharedPeak = primaryMemory?.SharedPeakBytes ?? 0;
        var highPressure = memory.CountersAvailable && dedicatedLimit > 0 && dedicatedPressure >= 92;
        var nearPressure = memory.CountersAvailable && dedicatedLimit > 0 && dedicatedPressure >= 85;
        var sharedSignificant = memory.CountersAvailable && sharedPeak >= Math.Max(512L * 1024 * 1024, (long)(dedicatedLimit * 0.08));

        var dumpBlob = latestDump is null ? "" : string.Join(" ", latestDump.Category, latestDump.ExceptionCode, latestDump.ExceptionName, latestDump.FaultingModule, latestDump.CoreReason, latestDump.Evidence);
        var oomDump = ContainsAny(dumpBlob, "0x8007000e", "e_outofmemory", "out of memory", "dxgi_error_out_of_memory", "显存不足", "内存不足");
        var driverDump = ContainsAny(dumpBlob, "nvwgf2umx", "nvlddmkm", "amdkmdag", "amdxx", "atidxx", "igd", "dxgi.dll", "d3d12.dll");

        var evidence = new List<string>();
        if (primaryMemory is not null)
            evidence.Add($"GPU Memory：Dedicated 峰值 {primaryMemory.DedicatedText}（{primaryMemory.DedicatedPressureText}），Shared 峰值 {primaryMemory.SharedText}。" +
                         (memory.CountersAvailable ? "" : " Windows GPU Adapter Memory counter 不可用，显存压力证据降级。"));
        if (!string.IsNullOrWhiteSpace(memory.Warning)) evidence.Add("显存计数器提示：" + memory.Warning);
        evidence.Add($"近 7 天：Display 4101={displayTdr}，GPU 驱动事件={vendorDriver}，LiveKernelEvent={liveKernel}，WHEA/PCIe={wheaPcie}，Kernel-Power 41={kernelPower}，无 BugCheck 式突然掉电={abrupt}。");
        if (pcieCorrelations > 0) evidence.Add($"时间关联：检测到 {pcieCorrelations} 组 GPU 故障与 PCIe WHEA 在 ±10 分钟内相邻。");
        if (powerCorrelations > 0) evidence.Add($"时间关联：检测到 {powerCorrelations} 组 GPU/PCIe 证据与异常断电记录在 ±30 分钟内相邻（Kernel-Power 41 通常在下次启动时记录，故只作为相关证据）。");
        evidence.Add("ReBAR：" + rebarEvidence);
        if (latestDump is not null) evidence.Add($"最近 Dump：{latestDump.ExceptionCode} / {latestDump.FaultingModule} / {latestDump.Category} / {latestDump.Confidence}。");
        var liveReports = payload.Array("LiveKernelReports").ToArray();
        if (liveReports.Length > 0) evidence.Add($"Windows LiveKernelReports 最近发现 {liveReports.Length} 个内核转储文件。最新：{liveReports[0].String("Folder")}/{liveReports[0].String("Name")}。");
        var tdrOverrides = payload.Array("TdrOverrides").ToArray();
        if (tdrOverrides.Length > 0) evidence.Add("检测到用户/工具设置的 TDR 调试注册表项：" + string.Join(", ", tdrOverrides.Select(x => $"{x.String("Name")}={x.String("Value")}")) + "。本程序不会自动修改这些键。");

        string code, title, confidence, summary;
        bool safeRepair;
        string repairLabel;
        List<string> plan;

        if ((highPressure && sharedSignificant) || oomDump)
        {
            code = "TRUE_VRAM_PRESSURE";
            title = "真爆显存 / 显存资源压力";
            confidence = highPressure && sharedSignificant && oomDump ? "HIGH" : "MEDIUM";
            summary = "Dedicated VRAM 已逼近物理显存上限并出现 Shared GPU Memory 溢出，或 Dump 直接包含内存分配失败证据。优先按真实显存压力处理，而不是先怪 ReBAR。";
            safeRepair = false;
            repairLabel = "无安全系统级自动修复";
            plan = ["降低纹理/光追/分辨率或高显存 Mod，关闭不必要 Overlay/录屏。", "复现时保持本页 GPU 诊断开启，对比 Dedicated 与 Shared 峰值。", "若单个游戏异常，优先核对该游戏补丁、材质包和显存泄漏，而不是修改 TDR。"];
        }
        else if (wheaPcie >= 2 || pcieCorrelations >= 1)
        {
            code = "PCIE_LINK";
            title = "PCIe 链路 / 硬件错误";
            confidence = (wheaPcie >= 2 && pcieCorrelations >= 1) || pcieCorrelations >= 2 ? "HIGH" : "MEDIUM";
            summary = pcieCorrelations > 0
                ? "WHEA 的 PCIe/Root Port 错误与 GPU/TDR 事件在同一时间窗口出现。优先检查 PCIe 链路、主板 BIOS/芯片组和显卡安装，而不是把黑屏简单归因于显存。"
                : "近 7 天重复出现 PCIe/Root Port WHEA，即使未与某一次 GPU 事件精确对齐，也足以形成链路稳定性警报。";
            safeRepair = false;
            repairLabel = "需要硬件/固件检查";
            plan = ["台式机检查显卡是否完全插紧、延长线/转接卡是否可靠；笔记本优先更新 OEM BIOS/EC/芯片组。", "恢复 PCIe/CPU/GPU 超频或降压到默认值后复测。", "持续出现 WHEA 17/18 时保留报告，不执行自动 DDU 或 DriverStore 删除。"];
        }
        else if ((abrupt >= 2 && powerCorrelations >= 1) || (abrupt >= 1 && powerCorrelations >= 1 && wheaFatal >= 1))
        {
            code = "POWER_DELIVERY_SUSPECTED";
            title = "供电 / 瞬时掉电嫌疑";
            confidence = "MEDIUM";
            summary = "异常断电式 Kernel-Power 41 与 GPU/PCIe/WHEA 证据在相邻时间窗口重复出现。Windows 无法直接测量 PSU/供电电压，因此这里只能判为供电/瞬态稳定性嫌疑，而不是软件能百分百确认的结论。";
            safeRepair = false;
            repairLabel = "不能安全自动修复供电";
            plan = ["检查电源额定功率、显卡供电插头和转接线，台式机尽量使用独立 PCIe/12V-2x6 线束。", "取消 GPU/CPU 超频与激进降压后复测。", "如果黑屏时整机直接断电/重启，优先做硬件供电排查而不是修改 Windows TDR。"];
        }
        else if (rebarEnabled && tdrEvidence >= 1 && !nearPressure && wheaPcie == 0 && abrupt == 0 && pcieCorrelations == 0)
        {
            code = "REBAR_COMPATIBILITY_SUSPECTED";
            title = "ReBAR 兼容性嫌疑";
            confidence = "MEDIUM";
            summary = "ReBAR 有较强启用证据，同时存在 GPU TDR/LiveKernel 证据，但没有真实显存饱和、PCIe WHEA 或突然掉电证据。当前只能判为兼容性嫌疑，需通过同版本驱动/同场景的 ReBAR 开关 A/B 复现确认。";
            safeRepair = false;
            repairLabel = "需要 BIOS A/B 验证";
            plan = ["保持游戏、驱动、画质完全一致，仅在 BIOS 中切换 ReBAR 做 A/B 复现。", "更新主板 BIOS、GPU VBIOS（仅使用 OEM 官方包）和显卡驱动后再次验证。", "程序不会自动写 BIOS、不会自动关闭 ReBAR，也不会把 256 MiB 小 BAR 以外的模糊证据当作确定结论。"];
        }
        else if (tdrEvidence >= 1 || driverDump)
        {
            code = "DRIVER_TDR";
            title = "显卡驱动 / TDR 崩溃";
            confidence = (displayTdr >= 1 && (vendorDriver >= 1 || liveKernel >= 1)) || driverDump ? "HIGH" : "MEDIUM";
            summary = "Display 4101、厂商显示驱动事件、LiveKernelEvent 或 Dump 模块共同指向显示驱动/GPU reset 路径。当前没有更强的显存、PCIe 或掉电证据覆盖它。";
            safeRepair = true;
            repairLabel = "执行安全 GPU 修复";
            plan = ["可自动清理 DirectX/厂商 Shader Cache（先改名备份）并执行 PnP 设备重扫描。", "自动修复不会 DDU、不会卸载显卡驱动、不会删除 DriverStore、不会修改 TdrDelay/TdrDdiDelay。", "若仍复现，再使用 GPU 厂商/OEM 官方驱动做人工更新或回退。"];
        }
        else if (nearPressure)
        {
            code = "VRAM_PRESSURE";
            title = "显存压力偏高";
            confidence = "MEDIUM";
            summary = "Dedicated VRAM 峰值已接近显存预算，但尚缺少 Shared GPU Memory 溢出或 Dump OOM 证据，先作为显存压力预警。";
            safeRepair = false;
            repairLabel = "无需系统级自动修复";
            plan = ["在问题游戏复现时再次运行 GPU 诊断，观察 Dedicated/Shared 是否继续上升。", "先降低纹理和高显存功能，验证黑屏/崩溃是否消失。"];
        }
        else
        {
            code = tdrEvidence == 0 && wheaPcie == 0 && abrupt == 0 ? "NO_STRONG_FAULT_EVIDENCE" : "EVIDENCE_INSUFFICIENT";
            title = code == "NO_STRONG_FAULT_EVIDENCE" ? "未发现明确 GPU 故障证据" : "证据不足，暂不能定因";
            confidence = "LOW";
            summary = "当前 7 天事件、显存采样和最近 Dump 没有形成足够强的单一根因链。建议在黑屏/崩溃后尽快重新运行诊断，以捕获显存峰值和相邻事件。";
            safeRepair = false;
            repairLabel = "暂无必要自动修复";
            plan = ["问题再次发生后尽快打开本页刷新；如能生成游戏 Dump，一并分析。", "不要仅凭一次 Kernel-Power 41、一次 ntdll/KERNELBASE 或“ReBAR 已开启”就下结论。"];
        }

        var memorySummary = primaryMemory is null
            ? "Windows 未返回可映射的 GPU memory adapter。"
            : $"{primaryMemory.Name}：Dedicated {primaryMemory.DedicatedText}（峰值 {primaryMemory.DedicatedPressureText}），Shared 峰值 {primaryMemory.SharedText}。";
        var eventText = $"4101={displayTdr} · VendorDriver={vendorDriver} · LiveKernel={liveKernel} · WHEA/PCIe={wheaPcie} · KernelPower41={kernelPower} · abrupt-like={abrupt}";
        var dumpText = latestDump is null ? "暂无本地 Dump 分析结果。" : $"{latestDump.FileName} · {latestDump.ExceptionCode} · {latestDump.FaultingModule} · {latestDump.Category} · {latestDump.Confidence}";

        return new GpuDiagnosisSnapshot
        {
            PrimaryCauseCode = code,
            PrimaryCauseTitle = title,
            Confidence = confidence,
            Summary = summary,
            RebarStatus = rebarStatus,
            RebarEvidence = rebarEvidence,
            MemorySummary = memorySummary,
            EventSummary = eventText,
            DumpSummary = dumpText,
            Evidence = evidence,
            RepairPlan = plan,
            SafeAutoRepairAvailable = safeRepair,
            SafeAutoRepairLabel = repairLabel,
            AnalyzedUtc = DateTimeOffset.UtcNow
        };
    }

    private static IReadOnlyList<DateTimeOffset> ParseTimes(JsonElement parent, string name)
    {
        if (parent.ValueKind != JsonValueKind.Object) return Array.Empty<DateTimeOffset>();
        var result = new List<DateTimeOffset>();
        foreach (var item in parent.Array(name))
        {
            if (DateTimeOffset.TryParse(item.ToString(), out var parsed)) result.Add(parsed.ToUniversalTime());
        }
        return result;
    }

    private static int CountNearPairs(IEnumerable<DateTimeOffset> left, IEnumerable<DateTimeOffset> right, TimeSpan window)
    {
        var a = left.Distinct().OrderBy(x => x).ToArray();
        var b = right.Distinct().OrderBy(x => x).ToArray();
        if (a.Length == 0 || b.Length == 0) return 0;
        var count = 0;
        foreach (var x in a)
        {
            if (b.Any(y => (x - y).Duration() <= window)) count++;
        }
        return count;
    }

    private static bool ContainsAny(string value, params string[] terms)
        => terms.Any(term => value.Contains(term, StringComparison.OrdinalIgnoreCase));

    public void Dispose() => _gate.Dispose();
}
