# v3.4.4

Build: `20260921.winui3.10`

## 修复

- 根据真实 Windows 11 构建日志修复 `.NET 10 SDK` 自动引导。
- 明确识别 WinGet `0x8A15000F / SOURCE_DATA_MISSING`，不再把 WinGet 源损坏误认为 SDK 包不存在。
- WinGet 安装前先执行非破坏性的 `winget source update --name winget`；不会自动 `source reset`。
- WinGet 失败、缺失或 SDK 仍不可见时，自动切换到 Microsoft 官方 `https://dot.net/v1/dotnet-install.ps1`。
- .NET 10 GA x64 SDK 安装到 `%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\dotnet10`，不依赖系统 PATH，不要求重新登录。
- SDK 检测改为多路径扫描：项目本地工具缓存、Program Files、Program Files (x86)、LocalAppData、当前 PATH。
- 下载官方安装脚本时支持 `Invoke-WebRequest`，失败后使用 `curl.exe` 回退。
- 新增构建链防回归测试：必须保留官方 SDK fallback、WinGet source update，并禁止自动 `winget source reset`。

## 不变的核心

- ASUS 4151/4152 RepairCenter、Eligibility、Recipe、Atomic Policy、Transaction、Observation、VERIFY 均未修改。
- PV / HOLTEK / ENE Legacy Adapter 继续 immutable hash-lock。
- GPU/ReBAR、VRAM、TDR、WHEA、Dump 诊断和 GPU Safe Repair 未修改。
- VC++ / DirectX、报告中心、SQLite 增量状态层未缩水。
