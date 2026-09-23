# 更新说明

## v4.6.4（候选）

- 安装器与本地构建入口接受 Windows 10 Build 19044+ x64，同时保留 Windows 11 x64 支持。
- 报告中心可复制实际运行路径、启动器路径、系统 Build 和 State 路径；启动器新增 `--diagnose-install`。
- Windows Server 2022 CI 对同一发布包重复安装与启动检查，并提供需要在干净 Windows 10/11 客户端 VM 执行的 E2E 脚本。真正的客户端兼容结论以该测试结果为准。

## v4.6.2

- 修复系统健康体检失败：`Get-SystemSnapshot` 在导入函数返回后丢失。引擎模块改为脚本作用域点源，哈希锁保留。
- 修复拆分后完整性检查误校验 SnapshotEngine 自身的问题，主引擎 SHA256 明确对应 RepairCenter.ps1。
- 统一 WPF 程序、启动器、安装包与后端版本号为 4.6.2。
- 新增 Windows PowerShell 5.1 导入与调用回归测试，验证函数作用域、引擎完整性和错误哈希拒绝，并接入 CI。

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
