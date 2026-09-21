# v3.4.2 Changelog

Build: `20260921.winui3.8`

## Windows PowerShell 5.1 static-gate hotfix

- Fixed the real Windows build failure observed after v3.4.1 launcher startup succeeded but `Architecture.Tests.ps1` exited before restore/publish.
- All JSON inputs used by the PS5.1 gate now use `System.IO.File.ReadAllText` with explicit strict UTF-8 decoding instead of Windows PowerShell default code-page decoding.
- Added a top-level fatal trap with exact script line and exception message.
- OneClick now captures child static-test stdout + stderr into `BuildLogs\StaticTests_*.log` and prints the captured output into the main transcript.
- ASUS RepairCenter / Atomic Policy / Recipe catalog / PV-HOLTEK-ENE adapters / GPU-ReBAR diagnostic core are unchanged.
- No DDU, no blind driver removal, no BIOS/ReBAR write, no TDR registry write.
