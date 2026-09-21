# Source Review v3.4.9

## Scope
Ship v3.4.8 compile fix through GitHub Actions as user-facing Setup.exe / Portable ZIP. Do not rewrite ASUS engines.

## GPU
`INSUFFICIENT_EVIDENCE` is renamed to the contracted token `EVIDENCE_INSUFFICIENT`. The five strong classes are unchanged. ReBAR still cannot be a root cause by itself. Kernel-Power 41 remains suspicion-only.

## P/Invoke
PDH `*W` and DbgHelp imports now use ExactSpelling. `PdhGetFormattedCounterArrayW` still uses `out uint itemCount` (CS1620).

## Release
Windows CI is the compiler. `PublishSingleFile` keeps native deps inside the EXE, but hash-locked `Backend` is copied beside it (`ExcludeFromSingleFile` + explicit materialize) so Recipe verification still sees RepairCenter.ps1 on disk. `main` produces GitHub Release artifacts after payload hash-lock verification.
