# 测试说明

当前仓库有四层检查，都在 Windows CI 里跑：

1. **静态不变量** `Tests/source_invariants.py`
2. **架构测试** `Tests/Architecture.Tests.ps1`
3. **Pester** `Tests/Unit/`（奥创重试失败路径、版本比较、GPU 厂商）
4. **.NET 单测** `Tests/WGR.Tests/`（注册表备份失败、着色器清理幂等）

发布后还会：

- 核对 `RELEASE_SHA256.txt`
- `Tests/E2E/Verify-ReleaseLayout.ps1`：ZIP 布局 + 解压后 `SelfHealingCenter.exe --version`

本地提交前请先模拟 CI：

```powershell
./Build-Release.ps1 -WhatIf
# 或
./tools/Preflight-Ci.ps1
```

改了 Backend 哈希锁定文件后：

```powershell
./tools/Update-HashLock.ps1
```
