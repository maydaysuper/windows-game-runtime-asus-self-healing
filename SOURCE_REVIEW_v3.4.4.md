# SOURCE REVIEW v3.4.4

本轮依据用户 Windows 11 25H2 / PowerShell 5.1 实机日志审查。

## 实机结论

v3.4.3 已通过全部 PowerShell Parser / XML / Architecture / Hash-Lock 静态门禁，失败点位于 `.NET 10 SDK` 自动安装阶段。WinGet 返回 `-1978335217`，对应 `0x8A15000F / SOURCE_DATA_MISSING`。

## 修改范围

仅修改构建引导和版本元数据：

- `OneClick-Win11.ps1`
- `Tests/Architecture.Tests.ps1`
- `Tests/source_invariants.py`
- BuildInfo 版本元数据与 BackendService fallback
- 文档 / Manifest

## 安全设计

- WinGet 只执行 `source update`，不自动 reset/remove source。
- WinGet 失败自动回退 Microsoft 官方 dotnet-install 脚本。
- 本地 SDK 安装为 per-user 工具缓存，不改机器级 PATH。
- 用户机器已有任意 .NET 安装均不会被卸载或覆盖。

## 核心完整性

与 v3.4.3 对比，RepairCenter、ElevatedBroker、AtomicPolicyExecutor、RecipeCatalog、PV/HOLTEK/ENE、GpuDiagnosticsReader、GpuSafeRepair 均保持相同 SHA256。
