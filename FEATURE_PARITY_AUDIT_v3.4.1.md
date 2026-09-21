# Feature parity audit — v3.4.1

## Scope

v3.4.1 is a launcher compatibility hotfix over v3.4.0. Product capabilities are intentionally unchanged.

## Protected ASUS core

- RepairCenter.ps1: `72a5def7d463ef0dd5ae3f0772ca4872c2759a32781661a636cdc08dc68013a8`
- PV Adapter: `bff8e7ded470438834f00eeb5efb4cae3312c8e6b919052a9a6161bb8a5f6a04`
- HOLTEK Adapter: `9217d88ee0632d3c36cc96e6c8edcaf5f156ab555da521511705f91dab6d2674`
- ENE Adapter: `b90eb3aba023d1fc73116b3400f7b4e66a4b2ead73799f9365096a4b3a5e9637`

All four hashes are unchanged from v3.4.0. RecipeCatalog and AtomicPolicyExecutor are unchanged as well.

## Other retained capabilities

- VC++ / DirectX detection and repair
- Incremental crash event ingestion
- WER LocalDumps configuration
- Local Minidump analysis
- ReBAR / Dedicated + Shared GPU memory / TDR / vendor driver / WHEA / PCIe / Kernel-Power / LiveKernelReports correlation
- GPU_SAFE_REPAIR rollback-oriented cache handling + PnP rescan
- SQLite Incident / Transaction / Component State / Workflow / Dump state
- Reports, reboot continuation, final verification and observation

## Hotfix-only changes

- Windows CMD launchers are ASCII-only, BOM-free, strict CRLF.
- Removed `chcp 65001` from CMD launchers.
- Added `Launch-Win11.cmd` ASCII filename alias.
- Normalized only non-core PowerShell build entry scripts to UTF-8 BOM + CRLF.
- Added launcher encoding regression tests.

No ASUS repair recipe, legacy adapter, GPU diagnosis rule or repair policy was removed or weakened.
