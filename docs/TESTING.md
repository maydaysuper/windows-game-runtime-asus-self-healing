# 测试说明

当前仓库有四层检查，都在 Windows CI 里跑：

1. **静态不变量** `Tests/source_invariants.py`
2. **架构测试** `Tests/Architecture.Tests.ps1`
3. **Pester** `Tests/Unit/`
   - 奥创 3 次全失败：`ErrorCode` 取最后一次，`ErrorHistory` 含 Attempt / Path / ErrorCode
   - 混合 Win32 错误码、非 Win32 的 HResult、多可执行文件轮换
   - 版本比较、GPU 厂商、原子策略路径
4. **.NET 单测** `Tests/WGR.Tests/`
   - 备份目录是文件 / 备份文件已存在 → 整次取消，注册表项不删
   - 逐项 `WriteRegistryBackup` 失败 → 跳过该项，不删
   - 卸载残留：先写 `.reg` 再删；受保护名称（Microsoft / 奥创）不删
   - 着色器：缺目录、空目录、连续三次、占用中的文件跳过、不删缓存根目录

发布后还会：

- 独立步骤 **Verify release SHA256**：核对 `RELEASE_SHA256.txt`
- 独立步骤 **E2E unzip portable and --version**：解压 ZIP，跑 `SelfHealingCenter.exe --version`
- **旧版 Python/Qt 升级 E2E**：安装包清理旧文件与快捷方式，同时保留 State。
- **Windows Server 2022 复测**：下载同一个发布包，在较旧的 Windows 内核上重复安装与启动检查。Server 测试不等于 Windows 10/11 客户端认证。

Windows 10 / 11 的发布验证还需要一台全新、可丢弃的 x64 客户端虚拟机（没有 .NET SDK），分别运行：

```powershell
./Tests/E2E/Verify-CleanClient.ps1 -SetupPath '.\Windows_Game_Runtime_ASUS_SelfHealing_Setup_v4.6.4_x64.exe' -ExpectedOS Win10 -DisposableClient
./Tests/E2E/Verify-CleanClient.ps1 -SetupPath '.\Windows_Game_Runtime_ASUS_SelfHealing_Setup_v4.6.4_x64.exe' -ExpectedOS Win11 -DisposableClient
```

每台虚拟机只执行对应的一行。脚本拒绝 Windows Server，核对实际系统 Build、安装后的启动器与内层 WPF 版本、真实路径、启动存活，以及 State 哨兵文件。测试会安装软件并保留安装目录用于排错，因此只在可丢弃的虚拟机上运行。Windows 10 最低 Build 19044（21H2 / Enterprise LTSC 2021）。普通 Windows 10 22H2 已结束微软常规支持；兼容性测试不延长操作系统本身的支持期。

本地提交前请先模拟 CI（避免再出现「6 个 PR 里 4 个在修 CI」）：

```powershell
./Build-Release.ps1 -WhatIf
# 或
./tools/Preflight-Ci.ps1
```

`-WhatIf` 会跑引用 / BOM / 不变量 / 架构 / Pester；在 Windows 且已装 SDK 时还会跑 `Tests/WGR.Tests`。不打包、不发布。

改了 Backend 哈希锁定文件后：

```powershell
./tools/Update-HashLock.ps1
```
