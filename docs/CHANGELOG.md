# 更新说明

## v4.6.1

- 注册表清理：备份写不进去就整次取消，不会先删后补。逐项备份失败则跳过该项。
- 奥创启动 3 次全失败会记下错误码和每次尝试（混合 Win32 码、HResult、多 EXE 轮换）。
- 着色器缓存清理可重复执行；缺目录 / 空目录 / 占用中的文件不会抛错。
- `Build-Release.ps1 -WhatIf` 本地预检，对齐 CI 静态/Pester 门；Windows 上顺带跑 WGR.Tests。
- CI 拆成独立步骤：SHA256 清单核对、便携包解压后 `SelfHealingCenter.exe --version`。

## v4.6.0

- 引擎拆成 RuntimeEngine（C++/DirectX）和 SnapshotEngine（快照/报告），RepairCenter 只做编排和哈希锁导入。
- OneClick 只负责环境/SDK，打包统一走 Build-Release。
- 发布包 E2E 核对照：ZIP 布局 + SHA256。
- 根目录文档收到 docs/。

## v4.5.2

- 后台脚本先按 RemoteSigned 跑，只有策略拦截才降到 Bypass。
- GitHub Actions 锁到 commit SHA。
- 并发/内存上限可在 appsettings.json 改。
- 下载 Microsoft 官方安装脚本后先算 SHA256 并校验内容。
- 发布包按 RELEASE_SHA256.txt 再核对一遍。
- 新增 `tools/Update-HashLock.ps1` 和 `docs/TESTING.md`。

## v4.5.1

- 注册表清理前自动备份 `.reg`，设置页可还原。
- 奥创启动失败会重试。
- CI 增加引用完整性 / BOM 检查。

## v4.5.0

- 奥创 501 / 装完打不开全自动修复。
- 着色器缓存清理、注册表残留清理。
