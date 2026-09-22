# v4.1 architecture

Frontend is **WPF / .NET 10 self-contained win-x64**. Windows App SDK is not loaded.

The shell keeps five primary entries and caches page instances so switching tabs does not re-run PowerShell. If `MainWindow` XAML fails to load, the same chrome is built in C#.

PowerShell Backend is split: `RepairCenter.ps1` orchestrates hash-locked modules (`RuntimeEngine.ps1` for VC++/DirectX, `SnapshotEngine.ps1` for snapshot/report, `ArmouryCrateSafeRepair.ps1` for 501/launch). Elevated Broker, RecipeCatalog and PV/HOLTEK/ENE hash-locks remain.

## Non-splittable boundary: RepairCenter embedded HAL payloads

`RepairCenter.ps1` 内嵌华硕 HAL 适配层（PV / HOLTEK / ENE）的 Base64 载荷。载荷与编排逻辑是**同一个哈希锚点**，禁止再拆成独立 `.psm1`。

双重锁定（仓库里没有单独的 `hash-lock.json`）：

1. `BuildInfo.json` / `BuildInfo.psd1` 的 `EngineSHA256` — 整份 `RepairCenter.ps1`（编排 + 内嵌 Base64）一个 SHA256。
2. `LEGACY_ADAPTER_LOCK.json` + `Tests/Architecture.Tests.ps1` — 同时核对磁盘上的 `module_*.ps1`、引擎里的期望哈希常量、以及内嵌 Base64 解码后的 SHA256。三者必须一致。

**禁止将载荷拆分为独立 `.psm1` 文件。** 原因：

1. 拆分会产生多个独立哈希锚点，检测粒度不变但维护复杂度上升。
2. 载荷与编排分离后，攻击者可单独篡改载荷文件而不触发编排层校验。
3. 组合关系无法用「各文件各自 SHA256」表达，需要引入 Merkle 树或签名机制，超出当前安全模型。

已经允许拆出、且**不含** HAL 载荷的模块：`RuntimeEngine.ps1`、`SnapshotEngine.ps1`。它们通过 `Import-HashLockedEngineModule` 按各自的 BuildInfo SHA 键导入。`ArmouryCrateSafeRepair.ps1` 同样独立哈希锁定，也不携带这三份 HAL 载荷。

要改载荷内容：改对应 `module_*.ps1`，同步改 `RepairCenter.ps1` 内嵌 Base64 和引擎常量，更新 `LEGACY_ADAPTER_LOCK.json`，跑 `./tools/Update-HashLock.ps1`，再通过 `Tests/Architecture.Tests.ps1`。缺任何一步都会被 CI 挡住。

# v4.0 / v3.4 architecture



## User-facing shell

Primary navigation stays intentionally small while capabilities remain complete:

1. System Health (`OverviewPage`)
2. ASUS Armoury (`SafetyPage`) — protected core capability
3. Game Runtime / C++ (`RuntimePage`)
4. Crash / GPU / ReBAR / Dump (`CrashPage`)
5. Reports (`ReportsPage`)

Developer-oriented deep diagnostics remain reachable from Advanced Settings and are not primary navigation targets.

## Standard-user frontend

WinUI 3 never performs PowerShell/WMI/Event Log/GPU sampling/Dump-heavy work synchronously on the UI thread. Main pages use an evictable navigation cache so repeated page switches do not force expensive reinitialization and low-memory systems can still reclaim pages.

## AdaptiveResourceGovernor

A process-local governor calculates a conservative profile from logical CPU count and GC available-memory budget:

- low-resource: one background heavy operation;
- normal/high-resource: at most two background heavy operations.

Read-only diagnostic child processes may run at BelowNormal priority. Elevated repair transactions are never hard-killed or paused merely to meet a performance target.

## Protected ASUS engine lane

`BackendService` serializes all `RepairCenter.ps1`-backed actions because engine import materializes verified legacy ASUS modules into a shared LocalAppData location. Hash validation is performed before execution.

The v3.4 GPU work does **not** rewrite the ASUS repair engine or the three legacy adapters. `RepairCenter.ps1`, PV, HOLTEK and ENE remain byte-for-byte hash-locked. Broker/Recipe/UiBridge only gain an additional, separately allow-listed `GPU_SAFE_REPAIR` route.

Do not extract the Base64 HAL payloads out of `RepairCenter.ps1`. That file is the single hash anchor for orchestration plus payloads; see **Non-splittable boundary** above.

## Incremental crash telemetry lane

`CRASH_DELTA` bypasses `RepairCenter.ps1`. `IncrementalEventReader.ps1` reads only the cursor delta plus a two-minute overlap, while SQLite stores and groups historical crash evidence.

## GPU / ReBAR evidence lane

`GPU_DIAGNOSTICS` also bypasses the large repair engine and uses a hash-locked read-only collector plus native C# telemetry:

- ReBAR evidence: NVIDIA BAR1 when `nvidia-smi` is available; otherwise assigned PCI memory-window evidence is treated conservatively and with lower confidence.
- Dedicated/Shared GPU Memory: bounded Windows PDH English-counter samples, mapped to DXGI adapters by LUID.
- GPU resets: Display 4101, NVIDIA/AMD/Intel display-driver providers and WER LiveKernelEvent evidence.
- PCIe: WHEA/Root-Port evidence.
- abrupt shutdown: Kernel-Power 41 is only supporting evidence, not proof of PSU failure.
- TDR overrides: read-only detection of user/debug registry overrides; the application never modifies them automatically.
- LiveKernelReports: newest accessible local dump is best-effort analyzed once per diagnostic run.

Root-cause classification requires combined evidence. GPU/TDR ↔ PCIe WHEA uses a bounded ±10-minute correlation window; GPU/PCIe ↔ abrupt shutdown uses ±30 minutes. A ReBAR-enabled signal by itself can never produce a ReBAR root-cause verdict.

## GPU safe-remediation boundary

Only the `DRIVER_TDR` software-side classification can expose automatic GPU remediation. The elevated recipe:

- rotates allow-listed user-level DirectX/NVIDIA/AMD shader caches into a rollback folder;
- recreates empty cache directories only after a successful move;
- skips locked caches instead of force deleting them;
- requests `pnputil /scan-devices`.

It never performs DDU, display-adapter uninstall/disable/restart, DriverStore deletion, BIOS/UEFI/ReBAR writes, TDR registry mutation, overclock/voltage/power-plan changes.

## Dump lane

`DumpAnalysisService` is fully local and read-only:

- `MemoryMappedFile` maps the dump without loading the entire file into the managed heap;
- Windows `Dbghelp.dll!MiniDumpReadDumpStream` reads exception and module streams;
- the exception address is mapped to the containing module;
- a conservative classifier produces category / confidence / likely direction;
- system exception endpoints such as ntdll/KERNELBASE are explicitly treated as low-confidence root-cause evidence.

No symbolized call stack is fabricated. When symbols are unavailable, reports call the output a core error point / likely direction.

## State store

SQLite schema v3 stores Event cursor/sync state, crash events, component state, repair transactions, incidents/observations, workflow current state/history and dump-analysis index. WAL uses `synchronous=NORMAL`, private connection cache, `wal_autocheckpoint=256`, `journal_size_limit=4 MiB` and bounded retention.

## Reports

`ReportService` writes local system-health, repair, Dump and GPU/ReBAR root-cause reports. Full diagnostic ZIP generation continues through the original protected RepairCenter export path.

## Repair authority boundary

System modifications remain exclusive to Elevated Broker. Broker validates BuildInfo, RecipeCatalog, AtomicPolicyExecutor and the selected recipe before executing. ASUS repair additionally retains its full Engine Eligibility and immutable adapter identity checks. Unknown ASUS versions remain `DIAGNOSE_ONLY`.


## v3.4.5 Windows publish hardening

The WinUI build is x64-only end-to-end: project metadata sets `Platform=x64`/`PlatformTarget=x64`, and OneClick passes `-p:Platform=x64` to restore and publish. Restore and publish emit separate text MSBuild logs and binary logs under `BuildLogs` for exact Windows-runner diagnostics.


## v3.4.6 release delivery

The production delivery lane is Windows-runner-only and emits two user artifacts from the same verified publish directory: a portable self-contained ZIP and a single Inno Setup installer EXE. The installer is per-user (`LocalAppData\Programs`) and does not weaken the elevated Broker boundary. Backend PowerShell files remain physical files under `Backend` so immutable hash-lock and Recipe verification semantics are unchanged.

The XAML regression gate also rejects direct `TextBox.HorizontalScrollBarVisibility` / `TextBox.VerticalScrollBarVisibility` members; WinUI 3 requires the `ScrollViewer.*ScrollBarVisibility` attached properties.



## v3.4.8 compile-blocker hotfix

v3.4.7 never produced a published WinUI payload on a real Windows 11 x64 / .NET 10 runner: `PdhGetFormattedCounterArrayW` call sites used `ref itemCount` against an `out uint itemCount` DllImport (`CS1620`). The XAML `WMC9999` error was a cascade from `_OnXamlPreCompileError`. v3.4.8 matches the call-site modifier, keeps PDH size-query semantics, and pins `PDH_FMT_COUNTERVALUE` to an explicit 16-byte x64 union. Static tests now lock both contracts.

## v3.4.7 verified release pipeline

Formal user binaries are emitted only after the Windows runner successfully completes WinUI build/publish and `Installer/Verify-PublishPayload.ps1` verifies the x64 PE plus the complete backend/legacy hash chain. `Build-Release.ps1` then produces the Portable ZIP, Setup EXE, `RELEASE_MANIFEST.json`, and SHA256 files. Local OneClick remains a developer/recovery fallback.
