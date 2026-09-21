# v3.4.1 Changelog

Build: `20260921.winui3.7`

## Windows launcher hotfix

- 修复 `一键构建并启动_Win11.cmd` 的 UTF-8 BOM：不再出现 `锘緻echo off`。
- 所有 `.cmd` 启动器改为 **ASCII-only + CRLF**，不再依赖 `chcp 65001`。
- 新增 ASCII 别名 `Launch-Win11.cmd`，中文路径仍可正常通过 `%~dp0` 传递给 PowerShell。
- `OneClick-Win11.ps1` / `Build-WinUI3.ps1` 保持 UTF-8 BOM，并规范为 CRLF，兼容 Windows PowerShell 5.1。
- 新增启动器编码/换行/入口脚本回归测试，后续再出现 BOM、LF-only 或 `chcp 65001` 会直接让静态测试失败。

## Safety / feature parity

- ASUS `RepairCenter.ps1`、PV/HOLTEK/ENE Legacy Adapter、Recipe、Atomic Policy 均未修改。
- ReBAR / VRAM / TDR / WHEA / Dump 诊断与 GPU_SAFE_REPAIR 能力未缩水。
- 本热修复只修改构建启动层、版本元数据、测试和说明文件。
