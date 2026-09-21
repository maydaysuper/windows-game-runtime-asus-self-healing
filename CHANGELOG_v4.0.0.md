# v4.0.0

Build: `20260922.wpf.1`

WinUI 3 unpackaged + Windows App SDK 2.5 在用户机器上连续 6 个版本无法启动（Fail Fast / XamlParseException / 原生闪退）。

v4.0.0 从 UI 层重铸为 **WPF + .NET 10 self-contained**：

- 不再引用 Windows App SDK / WinUI / PRI / generic.xaml
- 五个一级入口不变：系统健康 / ASUS 奥创中心 / 游戏运行库 / 崩溃 Dump / 报告中心
- PowerShell Backend、ASUS 4151/4152、Recipe / Atomic Policy / Elevated Broker 与 PV/HOLTEK/ENE hash-lock **未改**
