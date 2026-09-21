# v3.4.5

## Windows publish hotfix

- Confirmed v3.4.4 reaches .NET 10.0.401, restore, and fails only at WinUI publish.
- Pin MSBuild `Platform=x64` in both project metadata and restore/publish commands so Windows App SDK self-contained targets do not fall back to AnyCPU.
- Preserve unpackaged + self-contained + single-file deployment; no feature reduction.
- Add per-stage `Restore_*.log/.binlog` and `Publish_*.log/.binlog` under `BuildLogs` for exact MSBuild diagnostics.
- ASUS 4151/4152 engine, Broker, Atomic Policy, RecipeCatalog, PV/HOLTEK/ENE adapters, GPU/ReBAR diagnostics and GPU safe repair remain unchanged.
