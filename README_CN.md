# Windows Game Runtime / ASUS Armoury Self-Healing Center v4.1.0

## v4.1.0 底层重铸：WPF 可启动

WinUI 3 unpackaged 从 3.4.9 到 3.4.14 都无法在本机打开窗口。v4.1.0 前端是 WPF / .NET 10 自包含：

- 不再引用 Windows App SDK / WinUI / PRI / NavigationView
- 主窗口 XAML 失败时用纯 C# 构建同一套五入口壳
- 五个一级页面实例缓存
- ASUS 4151/4152 修复引擎、Recipe、PV/HOLTEK/ENE hash-lock **未改**

请卸载全部 3.4.x 后安装 4.1.0。

## 主界面

1. **系统健康**：0–100 本地健康指数。
2. **ASUS 奥创中心（核心）**：Armoury Crate / HAL / VGA / Holtek / ENE，Preflight、Dry Run、Eligibility、Elevated Broker。
3. **游戏运行库**：VC++ / DirectX 检测、官方包核对、签名校验、安全修复。
4. **崩溃 / GPU / ReBAR / Dump**：增量 Event Log、显存、ReBAR、TDR、WHEA、LiveKernel、Dump。
5. **报告中心**：系统/修复/Dump/GPU 报告、诊断 ZIP、重启续跑、最终验收。

## 安全边界

- 未知 ASUS 版本只诊断。
- 不会自动 DDU、写 BIOS/ReBAR、改 TDR、删 DriverStore。
- 只有 `DRIVER_TDR` 才开放安全 GPU 缓存回滚 + `pnputil /scan-devices`。

## 构建

普通用户请用 GitHub Release 的 Setup.exe。开发机双击 `Launch-Win11.cmd`。
