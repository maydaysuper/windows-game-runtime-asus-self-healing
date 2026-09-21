# Source review v3.4.0

## Scope

Review focused on the new ReBAR / VRAM / black-screen diagnosis, safe automatic remediation, preservation of ASUS repair behavior, performance impact and build/integrity boundaries.

## Findings resolved

### 1. Avoided “ReBAR enabled = root cause”

ReBAR is evidence only. The classifier requires GPU fault evidence while excluding stronger VRAM, PCIe/WHEA and abrupt-power signals before emitting `REBAR_COMPATIBILITY_SUSPECTED`. The result explicitly requires BIOS A/B reproduction for confirmation.

### 2. Avoided false PCIe/power correlation

Initial aggregate counts could have associated unrelated events from the same seven-day window. v3.4 now returns timestamp arrays and applies bounded correlation windows before raising stronger cross-signal conclusions.

### 3. Avoided unsafe TDR “fixes”

The application reads existing TDR debug overrides but never writes them. No automatic `TdrDelay`, `TdrDdiDelay` or `TdrLevel` tuning was introduced.

### 4. Avoided destructive driver remediation

The automatic repair path is limited to rollback-oriented shader-cache rotation plus PnP rescan. DDU, DriverStore deletion, display-adapter uninstall/disable/restart and BIOS/ReBAR writes remain prohibited.

### 5. Dump analysis remains bounded

LiveKernelReports discovery is read-only and automatic analysis is limited to one newest accessible dump. `DumpAnalysisService` uses `MemoryMappedFile` + DbgHelp streams and does not ingest the whole dump into the managed heap.

### 6. ASUS protected core retained

`RepairCenter.ps1` and the PV/HOLTEK/ENE modules are byte-for-byte unchanged from v3.3. Broker/Recipe changes are additive for the new GPU route.

## Modern engineering baseline retained

- .NET 10
- C# 14
- WinUI 3 / Windows App SDK 2.5.1
- Microsoft.Data.Sqlite 10.0.12
- Central Package Management
- nullable reference types
- .NET analyzers / code-style analysis
- NuGet direct and transitive dependency audit
- `GeneratedRegex`
- cancellable async background work
- bounded concurrency
- SQLite WAL / retention controls

No preview/RC runtime was adopted for the stable branch.

## Validation executed in this environment

- source capability/no-regression invariants: **179 PASS / 0 FAIL**;
- XAML/XML parsing: PASS;
- sync-over-async scan (`.Result`, `.Wait()`, `GetAwaiter().GetResult()`): PASS / none found;
- BuildInfo hash chain: PASS;
- immutable ASUS Engine/PV/HOLTEK/ENE hashes: PASS;
- v3.3 → v3.4 protected-core comparison: PASS.

## Validation intentionally deferred to Windows

This authoring environment is Linux and does not contain Windows PowerShell, .NET SDK or the WinUI XAML compiler. Therefore the report does not claim a local Windows binary compile. `OneClick-Win11.ps1` and `.github/workflows/windows-ci.yml` enforce Windows PowerShell Parser, architecture/hash-lock checks, NuGet restore/audit, WinUI build, self-contained publish, SHA256 and package creation on Windows.
