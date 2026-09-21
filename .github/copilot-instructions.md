# Copilot review instructions

This repository is a Windows 11 x64 WPF self-healing tool. Review PRs against these contracts.

## Do not break

- Hash-locked Backend: `RepairCenter.ps1`, `ElevatedBroker.ps1`, PV/HOLTEK/ENE modules, Recipe/Atomic Policy. Byte-identical unless the PR explicitly updates `BuildInfo` hashes.
- Five primary entries only: 系统健康 / ASUS 奥创中心 / 游戏运行库 / 崩溃 Dump / 报告中心.
- No auto-DDU, no BIOS/ReBAR/TDR writes. Unknown ASUS versions stay DIAGNOSE_ONLY.
- WPF host: `PublishSingleFile=false`, self-contained folder deploy. `wpfgfx_cor3.dll` must sit next to the inner EXE.
- User package layout: `SelfHealingCenter.exe` + `README.txt` + `App\`. Do not dump runtime DLLs at the ZIP root.
- Launch: desktop shortcut or portable EXE. Do not recreate Start Menu shortcuts.

## Prefer

- Keep Setup per-user (`PrivilegesRequired=lowest`). UAC only through Elevated Broker at repair time.
- Desktop launcher is net48 WinExe and only starts `App\WindowsGameRuntimeASUSSelfHealing.WinUI.exe` with that working directory.
- Chinese UI copy; YaHei-first font stack.
- New user-facing versions bump `BuildInfo.json` / `BuildInfo.psd1` together and refresh `BuildInfoSHA256`.
