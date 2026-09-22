# 奥创修复中心

Windows 11 x64 **WPF** tool for game runtime repair, **ASUS Armoury Crate 4151/4152** healing, plus safe cache/memory cleanup.

WinUI 3 unpackaged builds (v3.4.x) do not start on the target PC. v4.3.1 is WPF / .NET 10 self-contained.

**End users: do not compile this repo.** Download the latest GitHub Release:

- [Setup installer (recommended)](https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest)
- Portable ZIP is attached on the same release page

Uninstall every 3.4.x build first. Setup installs per-user under LocalAppData and puts **奥创修复中心** on the desktop. It does not add a Start Menu shortcut. Double-click the desktop icon, or unzip the portable folder and double-click `SelfHealingCenter.exe`. UAC appears only when an elevated ASUS / GPU repair actually runs.

## Current version

v4.3.1 · .NET 10 · C# 14 · WPF · desktop launcher + App folder

## What it does

1. System health
2. ASUS Armoury Crate (core)
3. VC++ / DirectX game runtimes
4. Crash / GPU diagnosis
5. Report center + system tools (cache / memory cleanup)
