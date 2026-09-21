# v3.4.12

Build: `20260922.winui3.18`

- **Hotfix: v3.4.11 弹 XamlParseException: XAML parsing failed。**
  Fail Fast 修掉后进程进入 Main，但 `App.xaml` 从未合并 `XamlControlsResources`。
  开发机上有共享 Windows App Runtime 时，Bootstrap 会把 WinUI generic.xaml 挂进包图，NavigationView / ThemeResource 碰巧能解析。
  自包含关掉 Bootstrap 后，这些样式不存在，MainWindow 一加载就 XamlParseException。
- `App.xaml` 按 WinUI 3 模板合并 `XamlControlsResources`。
- 标题栏 `SystemAccentColorLight2`（Color）改为 `SolidColorBrush`，不能直接当 Background。
- 显式打开 `WindowsAppSdkUndockedRegFreeWinRTInitialize`，并在 module initializer 里设置 `MICROSOFT_WINDOWSAPPRUNTIME_BASE_DIRECTORY`。
- 启动失败弹窗改为打印 InnerException 链。
- ASUS RepairCenter 与 PV/HOLTEK/ENE hash-lock 未改。
