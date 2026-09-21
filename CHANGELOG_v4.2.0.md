# v4.2.0

Build: `20260922.wpf.7`

最终运行版。启动方式和软件包收干净，功能和性能不砍。

## 启动

- 不再写入开始菜单
- Setup 装完在桌面放「自愈中心」图标，并可直接打开
- 便携版解压后双击 `SelfHealingCenter.exe`

## 软件包

用户看到的只有三样：

1. `SelfHealingCenter.exe`（桌面启动器）
2. `使用说明.txt`
3. `App\`（WPF 主程序 + Backend hash-lock，不要单独抽出来跑）

WPF 仍然是 self-contained 目录部署，禁止 PublishSingleFile。ASUS 4151/4152、PV / HOLTEK / ENE 字节锁定未改。

覆盖安装 4.1.x 即可。仍请先卸载全部 3.4.x。
