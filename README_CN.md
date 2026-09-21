# Windows Game Runtime / ASUS Armoury Self-Healing Center v4.1.2

## v4.1.2

WinUI 3 unpackaged 从 3.4.9 到 3.4.14 都无法在本机打开窗口。v4.1.0 换成 WPF 后窗口已能开。v4.1.2 修：

- 整页滚轮
- 官方包写清要不要修，并修掉 `$Host` 冲突
- 顶栏不再叠标题，中文不再被按钮框切字
- 软件图标
- 奥创中心只查 4151/4152 更新错误，不和首页抢体检

请卸载全部 3.4.x 后安装 4.1.2。已装 4.1.0 / 4.1.1 可直接覆盖。

## 主界面

1. **系统健康**：0–100 本地健康指数。奥创那一格只回答「有没有 4151/4152 更新错误」。
2. **ASUS 奥创中心（核心）**：只查 Armoury Crate 当前有没有更新错误；有才走 Dry Run / Eligibility / Elevated Broker。
3. **游戏运行库**：VC++ / DirectX 检测、官方包核对、签名校验、安全修复。官方包每张卡片写「不必修复」或「需要关注」。
4. **崩溃 / GPU / ReBAR / Dump**：增量 Event Log、显存、ReBAR、TDR、WHEA、LiveKernel、Dump。
5. **报告中心**：系统/修复/Dump/GPU 报告、诊断 ZIP、重启续跑、最终验收。

## 安全边界

- 未知 ASUS 版本只诊断。
- 不会自动 DDU、写 BIOS/ReBAR、改 TDR、删 DriverStore。
- 只有 `DRIVER_TDR` 才开放安全 GPU 缓存回滚 + `pnputil /scan-devices`。

## 构建

普通用户请用 GitHub Release 的 Setup.exe。开发机双击 `Launch-Win11.cmd`。
