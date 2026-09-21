# v4.1.1

Build: `20260922.wpf.3`

v4.1.0 窗口已经能开。这一版修使用中碰到的三个问题，ASUS 修复引擎字节级未动。

## 修复

- Dry Run /「检测并生成方案」不再因为上次流程停在 `RepairCompleted` 而报「非法修复流程跳转」
- Microsoft 官方包卡片在没取到安装器证据时显示 INFO，不再一律 WARN；并展示失败原因
- 中文界面改用 Segoe UI + 微软雅黑 UI，列表卡片不再叠字、首条不再被裁切
- 每次退出在 `%LocalAppData%\WindowsGameRuntimeASUSSelfHealing\Logs\` 写 `session-*.log`，记录本次 bug

## 保持不变

- ASUS 4151/4152 RepairCenter、Elevated Broker、Recipe / Atomic Policy
- PV / HOLTEK / ENE SHA256 hash-lock
- 不自动 DDU、不写 BIOS/ReBAR/TDR、未知 ASUS 版本只诊断

覆盖安装 4.1.0 即可。仍请先卸载全部 3.4.x。
