# Release Delivery v3.4.8

## Formal user artifacts
The normal user should receive prebuilt Windows artifacts produced by the Windows CI runner:

- `Windows_Game_Runtime_ASUS_SelfHealing_Setup_v3.4.8_x64.exe`
- `Windows_Game_Runtime_ASUS_SelfHealing_Portable_v3.4.8_win-x64.zip`
- `RELEASE_SHA256.txt`
- `RELEASE_MANIFEST.json`

Until CI emits those binaries, the patched source kit is:

- `Windows_Game_Runtime_ASUS_SelfHealing_WinUI3_v3.4.8_ReleaseKit.zip`

Run `一键构建并启动_Win11.cmd` / `Launch-Win11.cmd` on Windows 11 x64. v3.4.7 source cannot publish.

The source BuildKit and OneClick scripts are development/recovery artifacts, not the recommended end-user installation path once Setup/Portable exist.

## Trust boundary
The program cannot be distributed as a bare EXE because the hash-locked Backend directory is part of the repair trust chain. Setup/Portable both preserve this directory next to the main executable.

## Installation model
Setup installs per-user below `%LOCALAPPDATA%\\Programs\\WindowsGameRuntimeASUSSelfHealing` without requesting administrator privileges. Privileged ASUS/runtime/GPU repair operations remain isolated behind Elevated Broker and request UAC only at execution time.
