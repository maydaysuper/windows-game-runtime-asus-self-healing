# v3.4.0 Changelog

Build: `20260921.winui3.6`

## Added — ReBAR / GPU black-screen root-cause diagnostics

- Added hash-locked read-only `GpuDiagnosticsReader.ps1`.
- Added bounded native GPU-memory telemetry with Windows PDH English counters and DXGI adapter metadata.
- Added current/peak Dedicated GPU Memory and Shared GPU Memory evidence.
- Added conservative ReBAR evidence collection:
  - NVIDIA BAR1 when `nvidia-smi` is available;
  - assigned PCI memory-window evidence as a lower-confidence generic fallback.
- Added Display 4101, `nvlddmkm`, AMD, Intel display-driver provider evidence.
- Added WHEA/PCIe, Kernel-Power 41 and WER LiveKernelEvent evidence.
- Added detection of existing TDR debug/override registry values without modifying them.
- Added best-effort automatic analysis of the newest accessible `LiveKernelReports` dump.
- Added bounded temporal correlation:
  - GPU/TDR ↔ PCIe WHEA: ±10 minutes;
  - GPU/PCIe ↔ abrupt shutdown evidence: ±30 minutes.

## Root-cause classifier

The local classifier can produce the following principal outcomes with confidence and supporting evidence:

- `TRUE_VRAM_PRESSURE`
- `VRAM_PRESSURE`
- `DRIVER_TDR`
- `REBAR_COMPATIBILITY_SUSPECTED`
- `PCIE_LINK`
- `POWER_DELIVERY_SUSPECTED`
- `NO_STRONG_FAULT_EVIDENCE`
- `INSUFFICIENT_EVIDENCE`

ReBAR being enabled is never sufficient by itself to label ReBAR as the root cause. Kernel-Power 41 is never presented as direct proof of PSU failure.

## Added — safe GPU remediation

Added structured recipe `WINDOWS.GPU.SAFE_REPAIR.v1`, available only for the `DRIVER_TDR` software-side diagnosis.

It can:

- rotate allow-listed DirectX/NVIDIA/AMD Shader Cache directories into a timestamped rollback folder;
- recreate empty cache directories only after successful rotation;
- skip locked/in-use caches rather than force-delete them;
- execute `pnputil /scan-devices`.

It explicitly does **not**:

- run DDU;
- uninstall/disable/restart display adapters;
- remove DriverStore packages;
- write BIOS/UEFI/ReBAR settings;
- modify `TdrDelay`, `TdrDdiDelay`, `TdrLevel` or other TDR debugging values;
- change GPU clocks, voltage or Windows power plans.

## UI / reports

- Crash page renamed to **游戏崩溃 / GPU / ReBAR / Dump**.
- Added a user-readable root-cause summary, confidence, ReBAR evidence, memory evidence, event evidence, dump evidence and repair plan.
- Added a dedicated GPU/ReBAR report type in Report Center.
- GPU reports stay local and contain the evidence used by the classifier.

## Performance

- GPU memory sampling is bounded and on-demand rather than permanently polling.
- GPU event queries are provider-specific and capped.
- LiveKernel dump automatic analysis is limited to the newest accessible dump per diagnostic run.
- Existing adaptive concurrency, incremental Event Log cursoring, evictable navigation cache and bounded SQLite WAL remain in place.

## ASUS core preservation

The following protected ASUS artifacts are byte-for-byte unchanged from v3.3.0:

- `RepairCenter.ps1`
- `module_pv.ps1`
- `module_holtek.ps1`
- `module_ene.ps1`

`ElevatedBroker.ps1`, `RecipeCatalog.psd1`, `AtomicPolicyExecutor.ps1` and `UiBridge.ps1` changed only to add the separately allow-listed GPU safe-remediation/evidence routes. Existing ASUS Eligibility, hash-lock, Recipe and unknown-version safety remain intact.

## Validation

Local source-invariant validation: **179 PASS / 0 FAIL**.

Windows-native PowerShell parser, NuGet restore/audit, WinUI compile and publish remain enforced by the Windows one-click build and GitHub Actions Windows runner; they cannot be truthfully claimed as executed in the current Linux authoring environment.
