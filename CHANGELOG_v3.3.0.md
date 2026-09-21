# v3.3.0 Changelog

## No feature reduction / ASUS core protection

- Added shipped `CapabilityBaseline.json` with `NO_FEATURE_REDUCTION` policy and ASUS marked `CORE`.
- Baseline is SHA256 locked by BuildInfo and validated before backend execution.
- Verified `RepairCenter.ps1`, Elevated Broker, Atomic Policy, RecipeCatalog and PV/HOLTEK/ENE Legacy Adapters remain byte-identical to v3.1 stable.
- Restored user-accessible `VERIFY` final verification path that was unintentionally hidden by the v3.2 home-page consolidation.
- Restored full Transaction ID and open-transaction visibility inside Reports Center.

## Current stable technology baseline

- .NET 10 / C# 14.
- Microsoft.WindowsAppSDK 2.5.1.
- Microsoft.Windows.SDK.BuildTools.WinApp 0.6.1.
- Microsoft.Data.Sqlite 10.0.12.
- Added NuGet Central Package Management.
- Added NuGet direct/transitive audit and CI vulnerability warning gate.
- Added source capability/no-regression CI test before Windows build.

## UI / architecture

- Keeps 5-entry primary navigation: System Health + four business areas.
- Advanced diagnostic pages remain available under Advanced Settings.
- Build footer now reads runtime technology versions from BuildInfo instead of hard-coded UI text.

## Performance

- Retains adaptive 1–2 background heavy-task concurrency.
- Retains incremental Event Log, bounded SQLite WAL and memory-mapped Dump analysis.
- Does not enable preview/experimental framework packages or aggressive trimming merely to chase version numbers.
