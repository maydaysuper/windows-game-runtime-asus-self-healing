# Source review v3.3.0

## Result

The architecture remains WinUI 3 ordinary-user frontend + isolated PowerShell engine + Elevated Broker. The ASUS repair engine is intentionally not refactored in this release because its verified hash-lock is a safety boundary.

## Main findings

1. ASUS repair backend is unchanged from v3.1 stable; no 4151/4152 functionality was removed.
2. Runtime/Crash/Report functions were reorganized in v3.2 but not deleted.
3. One real regression was found: final `VERIFY` was no longer user reachable after the v3.2 home redesign. It is restored in Reports Center.
4. Transaction history had lost visible Transaction IDs after page consolidation; IDs and open-transaction status are restored.
5. Dependency versions are now centrally pinned and audited.
6. CapabilityBaseline makes future feature deletion a CI failure rather than a manual-review-only concern.

## Deliberate non-changes

- No automatic DDU.
- No blind driver/package removal.
- No old recipe applied to unknown ASUS versions.
- No modification to the three Legacy Adapter payloads.
- No preview/RC .NET runtime in production.
- No trimming or NativeAOT experiment for WinUI until Windows build/runtime benchmarks prove safe.
