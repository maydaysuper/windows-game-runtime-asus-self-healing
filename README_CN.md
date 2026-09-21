# Windows Game Runtime / ASUS Armoury Self-Healing Center v3.4.8

## v3.4.8 紧急修复：v3.4.7 无法在 Windows 上发布

v3.4.7 源码包的静态门禁全部通过，但 `dotnet publish` 在 `XamlPreCompile` 阶段失败（`CS1620`）。这不是环境问题，也不是 XAML 本体损坏：GPU 显存采样的 PDH P/Invoke 把第 4 参数声明成 `out`，调用却写成 `ref`。v3.4.8 修掉这个编译阻断，并给 PDH 结构体补上 x64 union 的显式布局。

请使用 **v3.4.8 源码包** 重新一键构建。ASUS 修复链、Recipe、PV/HOLTEK/ENE hash-lock 未改。

## 正式交付改为预编译安装包 / Portable

v3.4.7 不再把 OneClick 本机构建作为普通用户主路径。正式 Windows CI 会编译 WinUI 3、校验发布载荷、生成 **Setup 安装版 + Portable 便携版 + SHA256/Manifest**。安装前会再次验证 ASUS Engine/Broker/Recipe/CapabilityBaseline 与 PV/HOLTEK/ENE immutable hash-lock；任何漂移都阻止打包。

Setup 按当前用户安装到 LocalAppData，不需要管理员权限；真正执行 ASUS、运行库或允许的 GPU 修复时才由 Elevated Broker 请求 UAC。

技术基线继续保持 `.NET 10 + C# 14 + Windows App SDK 2.5.1 + SQLite 10.0.12`。安装器构建优先 Inno Setup 7 x64，并保留 Inno Setup 6 构建兼容回退。


## v3.4.6 正式交付方式

- 修复真实 WinUI XAML Compiler 报错：`TextBox` 的滚动条属性统一改为 `ScrollViewer.*ScrollBarVisibility` attached property。
- 正式发布不再要求普通用户自己构建：Windows CI 会直接产出 **Setup 安装包 EXE** 与 **Portable 自包含 ZIP**。
- Setup 采用当前用户安装目录，不要求安装阶段管理员权限；ASUS/运行库/GPU 修复仍只在实际操作时由 Elevated Broker 请求 UAC。
- 开发用 OneClick/BuildKit 继续保留，但不作为普通用户推荐入口。

# Windows Game Runtime / ASUS Armoury Self-Healing Center v3.4.6

v3.4.6 是 Windows 一键构建链可靠性热修复：静态门禁、ASUS、运行库、GPU/ReBAR、Dump、Transaction、Observation、最终验收与报告能力全部保留；新增 .NET 10 SDK 多路径引导。构建器不再把 WinGet 当作单点依赖，WinGet 源异常时会自动回退到 Microsoft 官方 dotnet-install.ps1，并把 SDK 安装到当前用户的本地工具缓存。继续坚持：**界面可以简化，能力不能缩水；ASUS Armoury Crate 4151/4152 自愈是第一核心能力。**

## 主界面

1. **系统健康**：0–100 本地健康指数，汇总 ASUS、游戏运行库、崩溃/GPU 与系统安全状态。
2. **ASUS 奥创中心（核心）**：Armoury Crate / HAL / VGA / Holtek / ENE 检测、Preflight、Dry Run、Eligibility、Recipe/Atomic Policy、Elevated Broker、安全修复、重启续跑、Observation 与最终验证。
3. **游戏运行库**：VC++ / DirectX 检测、Microsoft 官方包核对、签名校验、Load/API smoke test 与安全修复。
4. **崩溃 / GPU / ReBAR / Dump**：增量 Event Log、实时 Dedicated/Shared GPU Memory、ReBAR 证据、TDR/Display 4101、NVIDIA/AMD/Intel 驱动事件、WHEA/PCIe、Kernel-Power、LiveKernelReports、最新本机 LiveKernel minidump 最佳努力自动解析、普通 Minidump 分析与根因分类。
5. **报告中心**：系统健康报告、修复报告、Dump 报告、GPU/ReBAR 根因报告、完整诊断 ZIP、Transaction ID、未闭合事务、重启续跑、最终验收。

高级设置仍保留系统深度检查、组件身份诊断和安全/架构信息，只是不占一级导航。

## GPU / ReBAR 根因分类

程序不会因为 ReBAR 已开启就直接判定 ReBAR 是问题。它会把多类证据合并后再给出置信度：

- `TRUE_VRAM_PRESSURE`：Dedicated VRAM 高压 + Shared GPU Memory 明显上升，或 Dump 出现 OOM / DXGI out-of-memory 证据。
- `DRIVER_TDR`：Display 4101、`nvlddmkm` / AMD / Intel 显示驱动、LiveKernelEvent 或 Dump 指向 GPU reset / driver 路径。
- `REBAR_COMPATIBILITY_SUSPECTED`：ReBAR 有较强启用证据，同时有 TDR/LiveKernel，但没有显存饱和、PCIe WHEA 或突然掉电证据；必须通过 BIOS A/B 才能确认。
- `PCIE_LINK`：WHEA PCIe / Root Port 证据优先，提示检查链路、插槽、延长线、BIOS/芯片组和超频稳定性。
- `POWER_DELIVERY_SUSPECTED`：重复异常断电/重启与 GPU/WHEA 证据同时出现时只标记“供电嫌疑”。软件无法直接测量 PSU 电压，因此不会伪装成确定结论。

### 安全自动修复

只有证据落在 `DRIVER_TDR` 软件侧路径时才开放 **安全 GPU 修复**：

- 把 DirectX / NVIDIA / AMD Shader Cache **移动到可回滚备份目录**，再重建空缓存目录；锁定中的缓存直接跳过，不强删。
- 执行 `pnputil /scan-devices` 重新扫描 PnP。
- **不会**自动 DDU、卸载/禁用/重启显卡、删除 DriverStore、写 BIOS/UEFI/ReBAR、修改 `TdrDelay/TdrDdiDelay/TdrLevel`、改功耗/电压/频率。

如果分类为 ReBAR 兼容性、真实显存不足、PCIe 或供电，软件只给出验证步骤，不提供假的“一键修复”。

## 防缩水机制

- `Backend/CapabilityBaseline.json` 标记 `NO_FEATURE_REDUCTION`，ASUS 为 `CORE`；v3.4 将 GPU/ReBAR 能力也纳入功能基线。
- CapabilityBaseline 自身被 SHA256 写入 BuildInfo，并在运行前由 C# 后端完整性检查校验。
- CI 检查 ASUS / Runtime / Crash-Dump / GPU-ReBAR / Reports / Advanced Diagnostics 的必备入口与后端函数。
- ASUS `RepairCenter.ps1` 与 PV / HOLTEK / ENE Legacy Adapter 继续固定既有 SHA256；未知 ASUS 新版本固定 `DIAGNOSE_ONLY`。

## 当前稳定技术基线（2026-09-21）

- .NET 10
- C# 14
- WinUI 3 / Microsoft.WindowsAppSDK 2.5.1
- Microsoft.Windows.SDK.BuildTools.WinApp 0.6.1
- Microsoft.Data.Sqlite 10.0.12
- NuGet Central Package Management
- .NET analyzers + code-style build checks
- NuGet direct/transitive dependency audit
- `GeneratedRegex`、async/await、可取消后台任务、受控并发、SQLite WAL、MemoryMappedFile Dump 分析

项目使用**最新稳定主线**，不为了版本号追逐 .NET 11 RC/Preview 或 Windows App SDK Experimental。

## 性能策略

- UI 线程不执行 PowerShell / WMI / Event Log / GPU 采样 / Dump 重任务。
- 低配机器后台重任务最多 1 个，其他机器最多 2 个受控并发。
- Event Log 使用 SQLite cursor 增量读取；GPU 深度诊断只在用户触发/页面加载时做有界采样，不常驻高频轮询。
- GPU memory 采用 Windows PDH English counters + DXGI adapter metadata，采样窗口短且可取消。
- Dump 使用 `MemoryMappedFile + DbgHelp`，避免把大型 Dump 整体加载到托管堆。
- SQLite WAL 自动 checkpoint，并限制 journal 体积。
- 主页面使用可淘汰 NavigationCache，减少重复初始化而不永久钉住页面。

## Windows 11 x64 构建

双击：

`一键构建并启动_Win11.cmd`

会依次执行功能基线、PowerShell Parser、Architecture / Hash-Lock、NuGet restore/audit、WinUI Build、Publish、SHA256 和 ZIP 打包。


## v3.4.6 构建热修复

WinUI self-contained 发布现在从项目与命令行双重固定 `Platform=x64`，并输出独立 Restore/Publish MSBuild 日志与 binlog。
