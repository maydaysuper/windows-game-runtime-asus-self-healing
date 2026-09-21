# v3.4.11

Build: `20260922.winui3.17`

- **Hotfix: 安装后弹「快速异常检测失败 / Fail Fast Exception」，进程立即退出。**
  v3.4.10 虽然改成了文件夹自包含，但仍打开了 `WindowsAppSdkBootstrapInitialize=true`。
  该自动初始化在 `Main` 之前运行，去匹配本机已安装的 Windows App Runtime MSIX。
  自包含包本来就不走共享框架；匹配失败就 `Environment.FailFast`，异常处理程序不会执行，所以看不到 StartupGuard 弹窗和日志。
- 自包含 unpackaged 按 Microsoft 文档关闭 bootstrap / Deployment Manager 自动初始化。
  运行库从 EXE 旁边的 `Microsoft.ui.xaml.dll` / `Microsoft.WindowsAppRuntime.dll` 加载。
- 发布命令行同步钉死 `WindowsAppSdkBootstrapInitialize=false`，避免 CI 覆盖回 true。
- ASUS RepairCenter 与 PV/HOLTEK/ENE hash-lock 未改。
