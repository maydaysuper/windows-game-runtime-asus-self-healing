# Windows Game Runtime / ASUS Armoury Self-Healing Center v4.1.3

## v4.1.3

WinUI 3 unpackaged 从 3.4.9 到 3.4.14 都无法在本机打开窗口。v4.1.0 换成 WPF 后窗口已能开。v4.1.3：

- 运行库只检测本机 VC++ / DirectX
- 停用 Microsoft 官方安装器对比和自动修复
- 最终验收不再把「官方包拿不到」写成 WARN

请卸载全部 3.4.x 后安装 4.1.3。已装 4.1.x 可直接覆盖。

## 主界面

1. **系统健康**：0–100 本地健康指数。奥创那一格只回答「有没有 4151/4152 更新错误」。
2. **ASUS 奥创中心（核心）**：只查 Armoury Crate 当前有没有更新错误；有才走 Dry Run / Eligibility / Elevated Broker。
3. **游戏运行库**：本机 VC++ / DirectX 检测。不再下载官方安装器，也不再自动修复运行库。
4. **崩溃 / GPU / ReBAR / Dump**：增量 Event Log、显存、ReBAR、TDR、WHEA、LiveKernel、Dump。
5. **报告中心**：系统/修复/Dump/GPU 报告、诊断 ZIP、重启续跑、最终验收。
