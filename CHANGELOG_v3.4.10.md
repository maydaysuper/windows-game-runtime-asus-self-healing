# v3.4.10

Build: `20260922.winui3.16`

- **Hotfix: Setup / Portable 安装后打不开。** v3.4.9 把 WinUI 3 打成 `PublishSingleFile` 单文件 EXE（约 226 MB，旁边 0 个 DLL）。Windows App SDK 2.x 仍从 EXE 目录加载 `Microsoft.ui.xaml.dll` / `Microsoft.WindowsAppRuntime.dll`，而不是 `%TEMP%\.net` 解压目录，所以双击后进程立刻退出，没有任何窗口。
- 改为 unpackaged **文件夹自包含发布**：原生 DLL 与 EXE 同目录。Inno Setup 本来就会打包整个 publish 目录，单文件没有带来安装便利，只带来启动失败。
- 发布门禁现在强制检查 `Microsoft.ui.xaml.dll`、`Microsoft.WindowsAppRuntime.dll`、`e_sqlite3.dll` 以及 DLL 数量；再打成单文件会直接失败。
- 增加自定义 `Main` + 启动崩溃日志（`%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\Logs\startup-crash.log`）和 MessageBox，避免再出现静默退出。
- 快捷方式 / 安装完成启动显式 `WorkingDir={app}`。Backend 路径改用进程所在目录，不再依赖 `AppContext.BaseDirectory`。
- ASUS RepairCenter 与 PV/HOLTEK/ENE hash-lock 未改。
