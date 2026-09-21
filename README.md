# Windows Game Runtime / ASUS Armoury Self-Healing Center

Windows 11 x64 **WPF** tool for game runtime repair and **ASUS Armoury Crate 4151/4152** self-healing.

WinUI 3 unpackaged builds (v3.4.x) do not start on the target PC. v4.1.1 is WPF / .NET 10 self-contained.

**End users: do not compile this repo.** Download the latest GitHub Release:

- [Setup installer (recommended)](https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest)
- Portable ZIP is attached on the same release page

Uninstall every 3.4.x build first. Setup installs per-user under LocalAppData. UAC appears only when an elevated ASUS / runtime / GPU repair actually runs.

## Current version

v4.1.1 · .NET 10 · C# 14 · WPF · self-contained win-x64 folder deploy

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
