# Source Review — v3.4.3

## Scope
This hotfix is intentionally narrow: fix Windows PowerShell 5.1 source-text decoding in the static architecture/safety gate.

## Root cause confirmed from real Windows logs
`Architecture.Tests.ps1` used `Get-Content -Raw` for XAML/C#/PowerShell/project files. On Windows PowerShell 5.1, text without BOM is decoded using the active ANSI code page, so UTF-8 Chinese XAML became mojibake. XML validation then reported false `XML invalid` failures and text-based feature checks produced false negatives.

## Code changes
- Added a shared strict UTF-8 reader based on `System.IO.File.ReadAllText` + `UTF8Encoding(false, true)`.
- Removed BOM after decoding when present.
- Routed every static-test source-text read through `Read-Utf8Text`.
- `Read-Utf8Json` now reuses the same source reader.
- XAML/project XML validation now parses correctly decoded UTF-8 text.
- Updated version/build metadata to v3.4.3 / `20260921.winui3.9`.
- Updated `BackendService` fallback version to v3.4.3.

## Protected core
No changes were made to:
- RepairCenter.ps1
- ElevatedBroker.ps1
- AtomicPolicyExecutor.ps1
- RecipeCatalog.psd1
- module_pv.ps1
- module_holtek.ps1
- module_ene.ps1
- GpuDiagnosticsReader.ps1
- GpuSafeRepair.ps1

Their hashes are compared against v3.4.2 during packaging validation.
