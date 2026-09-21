# Source Review v3.4.10

## Scope
Fix v3.4.9 "installed but will not open". Do not rewrite ASUS engines.

## Root cause
Inspected GitHub Release `v3.4.9` Portable ZIP: 18 files, one 226 MB EXE, **zero DLLs**. That is `PublishSingleFile`. WinUI 3 / Windows App SDK 2.x unpackaged hosts probe `Microsoft.WindowsAppRuntime.dll` next to the real EXE, not the single-file extract directory. `WinExe` has no console, so the failure is silent.

Microsoft's unpackaged WinUI guidance already recommends wrapping a **folder** with Inno Setup. This repo already had Inno Setup; single-file was redundant and broken.

## Fix
- `PublishSingleFile=false`, keep `SelfContained` + `WindowsAppSDKSelfContained`.
- Payload verifier / CI / OneClick refuse a lone EXE.
- Custom `Program.Main` + `StartupGuard` write a crash log and MessageBox if managed startup still fails.
- Backend root uses `Environment.ProcessPath` / `StartupGuard.HostDirectory`.

## Unchanged
RepairCenter, ElevatedBroker, RecipeCatalog, PV/HOLTEK/ENE hashes, GPU classifier tokens.
