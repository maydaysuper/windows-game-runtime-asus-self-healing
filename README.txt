自愈中心 v4.2.0

推荐：安装版
1. 先卸载全部 3.4.x。已装 4.1.x / 4.2.x 可直接覆盖。
2. 运行 Setup。装完后桌面会有「自愈中心」图标。
3. 双击桌面图标即可。不会写入开始菜单。

便携版
1. 把整个文件夹解压到任意位置。不要只抽出 EXE。
2. 双击 SelfHealingCenter.exe（自愈中心）。
3. App 目录里的文件不要删，也不要单独拿出来运行。

五个入口
- 系统健康：总览。奥创那一格只回答有没有 4151/4152。
- ASUS 奥创中心：只查 Armoury Crate 当前有没有更新错误。
- 游戏运行库：只检测本机 VC++ / DirectX。
- 崩溃 / Dump：GPU / ReBAR 深度诊断。不会自动 DDU，不会改 BIOS。
- 报告中心：最终验收、诊断 ZIP、重启后续跑。

真正执行修复时才会弹 UAC。使用日志在关闭软件后写入：
%LocalAppData%\WindowsGameRuntimeASUSSelfHealing\Logs\session-latest.log
