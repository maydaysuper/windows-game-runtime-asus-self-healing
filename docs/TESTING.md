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
