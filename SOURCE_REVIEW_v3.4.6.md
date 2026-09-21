# Source Review v3.4.6

## Real Windows publish failure
`Publish_20260921_214519.log` reached the WinUI MarkupCompilePass1 stage and reported eight `WMC0011` errors. Every error was the same API misuse: direct `HorizontalScrollBarVisibility` / `VerticalScrollBarVisibility` members on `TextBox`. WinUI 3 exposes these through the `ScrollViewer` attached properties.

## Fix
- `ArchitecturePage.xaml`: 1 property fixed.
- `CrashPage.xaml`: 4 properties fixed.
- `IdentityPage.xaml`: 2 properties fixed.
- `SafetyPage.xaml`: 1 property fixed.
- Added PowerShell + Python regression gates for this exact compiler failure class.

## Release packaging
- Windows CI now pins `Platform=x64` in restore/build/publish.
- CI builds the self-contained publish directory.
- CI then creates a per-user Inno Setup `Setup.exe`.
- The same publish directory is also zipped as a portable release.

## Core safety
RepairCenter, ElevatedBroker, AtomicPolicyExecutor, RecipeCatalog, PV/HOLTEK/ENE adapters, GPU/ReBAR diagnostics and GPU safe repair were not modified by this fix.
