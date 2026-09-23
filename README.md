<p align="center">
  <img src="WindowsGameRuntimeASUSSelfHealing.WinUI/Assets/app.png" width="96" height="96" alt="奥创修复中心">
</p>

<h1 align="center">奥创修复中心</h1>

<p align="center">
  <strong>先检测，再修复。</strong><br>
  Windows 10 / 11 游戏运行库 · 华硕 Armoury Crate 更新错误 · 不乱装、不降级、不拷散 DLL
</p>

<p align="center">
  <a href="https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest"><img src="https://img.shields.io/github/v/release/maydaysuper/windows-game-runtime-asus-self-healing?label=最新版&color=c41e3a" alt="release"></a>
  <a href="https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases"><img src="https://img.shields.io/github/downloads/maydaysuper/windows-game-runtime-asus-self-healing/total?label=下载&color=111" alt="downloads"></a>
  <img src="https://img.shields.io/badge/Windows%2010%20%2F%2011-x64-0078D4" alt="Windows 10（Build 19044+）/ 11 x64">
  <img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT">
</p>

<p align="center">
  <a href="https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/download/v4.6.4/Windows_Game_Runtime_ASUS_SelfHealing_Setup_v4.6.4_x64.exe"><strong>下载安装包</strong></a>
  ·
  <a href="https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/download/v4.6.4/Windows_Game_Runtime_ASUS_SelfHealing_Portable_v4.6.4_win-x64.zip">便携版 ZIP</a>
  ·
  <a href="docs/README_CN.md">中文说明</a>
  ·
  <a href="#english">English</a>
</p>

---

市面上的运行库工具大多是「一键全装」。奥创修复中心反过来：**先看本机真实文件，再联网对比微软官方版本，不一样才修，修完立刻再验一次。**

华硕玩家多出来的那一块也覆盖了：Armoury Crate 安装 501、装完打不开、更新失败（4151 / 4152）。只查现在有没有错，不把旧方案乱套上去。

文档：[架构](docs/ARCHITECTURE.md) · [更新说明](docs/CHANGELOG.md) · [测试](docs/TESTING.md) · [中文说明](docs/README_CN.md)

## 直接用，不要编译

普通用户**不要从源码编译**。到 [Releases](https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest) 下载 GitHub Actions 打出来的官方包。

| 包 | 给谁 |
|---|---|
| `Setup_v4.6.4_x64.exe` | 推荐。装到当前用户目录，桌面生成「奥创修复中心」图标 |
| `Portable_v4.6.4_win-x64.zip` | 解压后双击 `SelfHealingCenter.exe` |

- 请先卸载全部 **3.4.x**（WinUI 版在部分机器上无法启动）
- 已装 4.1–4.6.3 可直接覆盖
- 不往开始菜单塞快捷方式
- 只有真正需要提权的修复才会弹出 UAC

当前版本：**v4.6.4** · .NET 10 · WPF · Windows 10（Build 19044+）/ 11 x64。Windows 10 普通版本已结束微软常规支持；建议使用仍受支持的企业 LTSC 或加入 ESU 的系统。

## 五个页面，一眼看懂结果

1. **系统健康** — 正不正常，一句话
2. **奥创中心** — 安装 501、装完打不开、更新错误，点「全自动修复」
3. **游戏运行库** — 本机 C++ 文件 vs 微软官方；不一样就问你要不要修
4. **游戏崩溃** — 看为什么崩，不乱卸显卡驱动
5. **报告中心** — 再检查一遍、诊断包、复制实际安装路径、缓存 / 着色器 / 注册表 / 内存清理（不结束正在运行的程序）

## 和合集包、DirectX Repair 的差别

| | 奥创修复中心 | VC++ AIO 合集 | DirectX Repair |
|---|---|---|---|
| 策略 | 先检测，再按需修 | 2005–2026 全装 | 一键补 DX / C++ |
| C++ 依据 | 真实文件 + 能否加载 + 官方版本 | 安装器清单 | 本地组件包 |
| 官方对比 | 联网对比微软当前版本 | 装到包内版本 | 基本不比 |
| 降级 | 已经新于官方就不动 | 可能重装 | 可能重装 |
| 散 DLL 拷进系统目录 | 不做 | 不做（正规 AIO） | 部分流程会补文件 |
| 华硕 4151 / 4152 | 有 | 无 | 无 |
| 修完再验 | 立刻再看文件 | 无 | 无 |

适合：游戏报缺 `VCRUNTIME140` / `MSVCP140`、奥创中心更新失败、想确认「现在到底要不要修」。

不替代：刚重装系统、什么库都没有时，可以先用微软官方安装器或正规 AIO 打底，再用奥创盯着。

## 不会做什么

- 不把零散 DLL 拷进 `System32`
- 不降级已经新于官方的运行库
- 不卸载显卡驱动、不改主板 / BIOS
- 不结束正在运行的游戏和软件
- 注册表只删指向已经不存在文件的残留

修复 C++ 只用微软签名的官方安装器（本机缓存 / `winget` / 官方下载），不是网盘合集。

## 源码与校验

引擎文件有哈希锁定。安装包附带 `RELEASE_SHA256.txt`。Issue 请尽量带报告中心导出的诊断包。

开发提交前在 Windows 上先模拟 CI，不要直接推：

```powershell
./Build-Release.ps1 -WhatIf
```

这会跑引用完整性、UTF-8 BOM、`source_invariants`、架构测试、Pester，以及（有 SDK 时）`Tests/WGR.Tests`。不打包。CI 还会核 `RELEASE_SHA256.txt`，并解压便携包跑 `--version`。

```text
maydaysuper/windows-game-runtime-asus-self-healing
MIT License · 2026
```

---

<a id="english"></a>

## English

**Ultron Repair Center** is a Windows 10 (build 19044+) / Windows 11 x64 tool that **detects first, then repairs**.

It checks real Visual C++ files on disk (not just registry), compares them with Microsoft’s current official version, and only then runs the official installer. After repair it re-checks immediately. It also inspects **ASUS Armoury Crate 4151/4152** update failures — current errors only, no leftover “old recipe” repair.

Download the GitHub Actions build from [Releases](https://github.com/maydaysuper/windows-game-runtime-asus-self-healing/releases/latest). Do not compile this repo unless you are developing it. Uninstall every 3.4.x build first.

It does **not** copy loose DLLs into System32, does **not** downgrade a newer runtime, and does **not** uninstall GPU drivers.
