# Windows Game Runtime / ASUS Armoury Self-Healing Center

Windows 11 x64 WinUI 3 tool for game runtime repair and **ASUS Armoury Crate 4151/4152** self-healing.

**End users: do not compile this repo.** Download the latest GitHub Release:

- [Setup installer (recommended)](https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest)
- Portable ZIP is attached on the same release page

Setup installs per-user under LocalAppData. UAC appears only when an elevated ASUS / runtime / GPU repair actually runs.

## Current version

v3.4.9 · .NET 10 · C# 14 · Windows App SDK 2.5.1 · self-contained win-x64

## What it does

1. System health
2. ASUS Armoury Crate (core)
3. VC++ / DirectX game runtimes
4. Crash / GPU / ReBAR / Dump
5. Report center

Unknown ASUS versions stay **diagnose-only**. The tool never auto-DDU, never writes BIOS/ReBAR/TDR, and never deletes DriverStore.

## Build (developers / CI only)

Windows 11 x64. GitHub Actions is the official compiler.

```text
Launch-Win11.cmd
```

## License

MIT. See [LICENSE](LICENSE).
