# Release Delivery v4.2.0

## Formal user artifacts
The normal user should receive prebuilt Windows artifacts produced by the Windows CI runner:

- `Windows_Game_Runtime_ASUS_SelfHealing_Setup_v4.2.0_x64.exe`
- `Windows_Game_Runtime_ASUS_SelfHealing_Portable_v4.2.0_win-x64.zip`
- `RELEASE_SHA256.txt`
- `RELEASE_MANIFEST.json`

Setup installs per-user, creates a desktop shortcut named 自愈中心, and does **not** add a Start Menu item. Portable ZIP extracts to:

```text
SelfHealingCenter.exe
README.txt
App\   (WPF host + Backend hash-lock)
```

Double-click `SelfHealingCenter.exe`. Do not run the inner EXE from `App\` alone.

## Trust boundary
The program cannot be distributed as a bare EXE because the hash-locked Backend directory is part of the repair trust chain. The inner WPF host stays a self-contained folder (`PublishSingleFile=false`). The desktop launcher is a tiny net48 WinExe that only sets the working directory and starts that host.

## Installation model
Setup installs per-user below `%LOCALAPPDATA%\Programs\WindowsGameRuntimeASUSSelfHealing` without requesting administrator privileges. Privileged ASUS/GPU repair operations remain isolated behind Elevated Broker and request UAC only at execution time.
