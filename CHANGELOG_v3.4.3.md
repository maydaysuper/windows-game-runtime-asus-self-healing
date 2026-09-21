# v3.4.3 Hotfix

## 修复
- 修复 Windows PowerShell 5.1 在中文系统上使用 `Get-Content -Raw` 按本地代码页读取 UTF-8 XAML/C#/PowerShell 源文件，导致静态测试把合法 XAML 误判为 XML invalid 的问题。
- `Tests/Architecture.Tests.ps1` 新增统一 `Read-Utf8Text` 严格 UTF-8 文本读取器。
- XAML/XML 校验、C# async 扫描、UI 功能基线、报告中心、GPU/ReBAR 安全基线等源码读取全部改为显式 UTF-8。
- JSON 基线继续复用相同 UTF-8 读取链。
- 保留独立 `StaticTests_*.log`，真实 Windows 失败可直接定位。

## 未改动
- ASUS RepairCenter 核心
- Elevated Broker
- Atomic Policy / RecipeCatalog
- PV / HOLTEK / ENE Legacy Adapter
- GPU/ReBAR 诊断与 GPU Safe Repair

因此 ASUS 4151/4152 修复链和所有 Legacy hash-lock 均保持原值。
