# v4.1.4

Build: `20260922.wpf.6`

Microsoft 官方 VC++ / DirectX 安装器对比一直拿不到包。这一版把无法对比、也无法修复的部分彻底阉割。

## 变更

- 不再下载 aka.ms / download.microsoft.com 的 vc_redist / dxwebsetup
- 运行库健康只看本机注册表和 DLL。正常就是 PASS，最终验收不再因此标 WARN
- `RUNTIME_ONLINE` / `PLAN_RUNTIME` / `RUNTIME_REPAIR` 仍保留接口名，但一律拒绝下载和自动修复
- 本机文件真的坏了：验收标 FAIL，请自行安装 Visual C++ Redistributable / DirectX End-User Runtime

ASUS 4151/4152、PV / HOLTEK / ENE hash-lock 未改。

覆盖安装 4.1.x 即可。仍请先卸载全部 3.4.x。
