# v4.1.3

Build: `20260922.wpf.5`

本机 VC++ / DirectX 已经可用时，不再因为拿不到 Microsoft 官方安装器而标 WARN，也不再提供官方包对比和自动修复。

## 变更

- 运行库健康只看本机 DLL / 注册表。关键文件正常即为 PASS
- 最终验收把 INFO 视为通过，不再把「还没联网对比」写成 WARN
- 去掉「联网对比 / Dry Run / 安全修复」和官方包卡片
- 本机文件真的坏了：验收仍会标出来，但请自行安装 Visual C++ Redistributable / DirectX End-User Runtime

ASUS 4151/4152、PV / HOLTEK / ENE hash-lock 未改。

覆盖安装 4.1.x 即可。仍请先卸载全部 3.4.x。
