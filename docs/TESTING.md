# 测试说明

当前仓库有三层检查，都在 Windows CI 里跑：

1. **静态不变量** `Tests/source_invariants.py`  
   哈希锁、版本、禁止 DDU、页面契约、BOM/引用脚本是否存在。
2. **架构测试** `Tests/Architecture.Tests.ps1`  
   PowerShell 解析、XML、启动脚本 CRLF、allowlist 谓词。
3. **Pester** `Tests/Unit/`  
   奥创 501 启动重试、GPU 厂商识别、原子策略路径。

发布后还会核对 `artifacts/release/RELEASE_SHA256.txt` 与安装包 FileVersion。

本地：

```powershell
python Tests/source_invariants.py
./Tests/Architecture.Tests.ps1
./tools/Check-FileReferences.ps1
./tools/Ensure-BOM.ps1 -Verify
Invoke-Pester -Path Tests/Unit
```

改了 Backend 哈希锁定文件后，先跑：

```powershell
./tools/Update-HashLock.ps1
```


发布布局：

```powershell
./Tests/E2E/Verify-ReleaseLayout.ps1 -ReleaseDir artifacts/release
```
