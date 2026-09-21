# Feature parity audit — v3.4.0

## Result

**PASS — v3.4 adds GPU/ReBAR diagnostics without reducing the existing ASUS, runtime, crash/dump or report capabilities.**

## Protected ASUS core

Compared with the v3.3.0 source baseline, hashes remain identical:

| Artifact | SHA256 | Result |
|---|---|---|
| `RepairCenter.ps1` | `72a5def7d463ef0dd5ae3f0772ca4872c2759a32781661a636cdc08dc68013a8` | unchanged |
| `module_pv.ps1` | `bff8e7ded470438834f00eeb5efb4cae3312c8e6b919052a9a6161bb8a5f6a04` | unchanged |
| `module_holtek.ps1` | `9217d88ee0632d3c36cc96e6c8edcaf5f156ab555da521511705f91dab6d2674` | unchanged |
| `module_ene.ps1` | `b90eb3aba023d1fc73116b3400f7b4e66a4b2ead73799f9365096a4b3a5e9637` | unchanged |

### Additive Broker change

The v3.4 Broker diff adds only:

- allow-list member `GPU_SAFE_REPAIR`;
- structured `GPU_SAFE` Recipe validation;
- hash validation and loading of `GpuSafeRepair.ps1`;
- one new `GPU_SAFE_REPAIR` switch branch.

Existing ASUS Broker branches and ASUS repair invocation remain unchanged.

### Additive Recipe change

`RecipeCatalog.psd1` adds `GPU_SAFE`. Existing `PV`, `HOLTEK`, `ENE`, `RUNTIME` recipes and the global policy preserving `DIAGNOSE_ONLY`, no automatic DDU and no blind driver removal remain intact.

## Existing user capabilities retained

- ASUS: Preflight, Dry Run, PLAN_ASUS, Eligibility, Elevated repair, reboot continuation, Observation and final VERIFY.
- Runtime: VC++/DirectX inspection and trusted runtime repair.
- Crash/Dump: incremental Event Log, WER LocalDumps, local minidump analysis.
- Reports: system health, repair/Transaction, Dump, full diagnostic ZIP, reboot continuation and final verification.
- Advanced: deep test, component identity and architecture pages remain reachable from Advanced Settings.

## v3.4 additions

- `GPU_DIAGNOSTICS` read-only backend action.
- `GPU_SAFE_REPAIR` elevated, separately recipe-gated action.
- Dedicated/Shared GPU Memory native telemetry.
- ReBAR evidence.
- TDR/vendor-driver/WHEA/PCIe/Kernel-Power/LiveKernel evidence.
- temporal-correlation guard against false cross-event attribution.
- GPU/ReBAR report generation.

## Regression gate

`CapabilityBaseline.json` remains hash-locked and now includes the new GPU/ReBAR actions/services/safety rules. The Python source invariants and Windows PowerShell architecture tests fail the build if required ASUS/runtime/crash/GPU/report capabilities disappear.
