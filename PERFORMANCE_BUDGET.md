# v3.4 performance budget / adaptive resource policy

These are engineering budgets, not absolute guarantees for every PC. v3.4 continues to prefer **bounded concurrency, incremental reads and on-demand sampling** over permanent background polling.

| Area | Target | v3.4 strategy |
|---|---:|---|
| Shell cold start | normal Win11 NVMe: interactive shell target < 1.5 s | startup does not run full Event Log/WMI/GPU scans |
| Main navigation | perceived < 100 ms | five primary pages use evictable NavigationCache |
| Idle CPU | soft target < 0.5% average | no busy loop; no persistent high-frequency GPU sampler |
| Heavy background work | low-end max 1; other systems max 2 | `AdaptiveResourceGovernor` based on CPU + GC memory budget |
| Event Log | incremental | SQLite cursor + 2-minute overlap |
| GPU memory sample | bounded/on demand | five ~300 ms PDH samples; cancellation-aware |
| GPU evidence scan | bounded/on demand | provider-specific capped event queries; no full history scan |
| LiveKernel dump | max one auto-analysis per GPU diagnostic run | MemoryMappedFile; failure degrades gracefully |
| Dump analysis memory | do not read full dump into managed heap | MemoryMappedFile + DbgHelp stream reader |
| SQLite WAL | bounded | `wal_autocheckpoint=256` + `journal_size_limit=4 MiB` |
| Resident working set | soft target < 160–180 MB in normal use | bounded lists, evictable pages, history persisted in SQLite |
| Database size | normal-use soft target < 50 MB | tiered retention/pruning |

## Adaptive profiles

- **Low resource**: <=4 logical cores or <=8 GB GC available-memory budget; heavy diagnostics strictly serialized and read-only child processes lowered in priority.
- **Balanced**: typical 6–10 core / 16 GB machines; at most two independent background diagnostic operations.
- **High-performance**: still capped at two heavy background tasks; the diagnostic center should never become the workload being diagnosed.

Elevated MSI/DISM/ASUS repair transactions are not forcibly paused or killed for performance reasons; transaction consistency wins over a benchmark target.

## GPU diagnostic cost controls

- No permanent ReBAR/VRAM polling service.
- ReBAR evidence and WHEA/TDR scans run on page load/explicit refresh, not continuously while the application is idle.
- PDH sampling is short-lived and native; samples are aggregated by adapter LUID.
- `LiveKernelReports` parsing is best-effort and limited to the newest accessible dump not already in SQLite.
- Time-correlation operates on capped timestamp arrays, avoiding expensive full-log joins.

## Build/publish trade-offs

- `self-contained folder deploy` (not PublishSingleFile). WinUI native DLLs must sit next to the EXE; Inno Setup already wraps the folder.
- `PublishTrimmed=false`: WinUI/Windows Runtime compatibility is preferred over risky trimming.
- `PublishReadyToRun=false`: avoids inflating package size until Windows A/B startup measurements demonstrate a worthwhile gain.
- Stable dependency versions stay centralized in `Directory.Packages.props`; NuGet direct/transitive audit remains enabled.
