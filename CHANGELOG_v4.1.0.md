# v4.1.0

Build: `20260922.wpf.2`

WinUI 3 unpackaged 从 v3.4.9 到 v3.4.14 连续无法在用户机器启动。v4.0.0 已换成 WPF，v4.1.0 从壳层把启动路径再夯实一遍。

## 重铸

- 主窗口 XAML 解析失败时用纯 C# 构建同一套五入口壳，不再依赖 WASDK / PRI / NavigationView
- 五个一级页面实例缓存，来回切换不再重复初始化 PowerShell 体检
- 启动探测改为 WPF 原生库（`wpfgfx_cor3.dll` / `PresentationNative_cor3.dll` / `e_sqlite3.dll`），去掉 Windows App Runtime 环境变量
- 列表去 Win32 默认铬边；按钮、文本框、状态条按诊断台样式重画

## 保持不变

- ASUS 4151/4152 RepairCenter、Elevated Broker、Recipe / Atomic Policy
- PV / HOLTEK / ENE SHA256 hash-lock
- 游戏运行库、崩溃 / GPU / ReBAR / Dump、报告中心、高级诊断
- 不自动 DDU、不写 BIOS/ReBAR/TDR、未知 ASUS 版本只诊断

请卸载全部 3.4.x 后安装 4.1.0。
