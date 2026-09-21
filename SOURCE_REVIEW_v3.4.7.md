# Source Review v3.4.7

## Scope
v3.4.7 is a release-engineering hardening pass after v3.4.6 fixed the real WinUI XAML compiler failures. It does not redesign the diagnostic/repair engines.

## Release trust chain
Before Portable or Setup artifacts can be produced, the published payload verifier checks:
- main EXE exists and is an x64 PE;
- EXE file version matches BuildInfo;
- Engine, Broker, Bootstrap, UiBridge, event reader, GPU reader/safe repair, Atomic Policy, RecipeCatalog, BuildInfo.psd1, and CapabilityBaseline match BuildInfo SHA256 values;
- PV/HOLTEK/ENE module files match the immutable legacy hashes;
- a publish payload SHA256 manifest is generated.

## Installer
The Setup definition is per-user (`PrivilegesRequired=lowest`) and installs below LocalAppData. The program itself stays non-elevated. Existing repair behavior remains brokered and UAC is requested only for privileged repair operations.

## CI
The Windows runner is now the source of truth for user-facing binaries. A successful run produces a prebuilt Portable ZIP and Setup EXE plus manifests/hashes. Local OneClick remains a development/diagnostic fallback only.

## Functional integrity
Core backend files and their hashes are unchanged from v3.4.6. UI simplification does not remove ASUS 4151/4152, runtime, crash/Dump, ReBAR/GPU, transaction/observation, final verification, or report capabilities.
