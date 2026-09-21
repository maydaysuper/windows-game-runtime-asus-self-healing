# v3.4.8

Build: `20260921.winui3.14`

- **Hotfix: WinUI 3 / .NET 10 发布失败。** v3.4.7 在 `XamlPreCompile` 阶段被 `CS1620` 拦住，无法生成 Setup / Portable。
- 根因：`GpuMemoryTelemetryService` 把 `PdhGetFormattedCounterArrayW` 第 4 参数声明为 `out uint itemCount`，调用处却写成 `ref itemCount`。这是 C# 语言层错误，和 PDH ABI 无关。
- 连带 `WMC9999`（XAML Compiler 空引用）是预编译失败后的级联，不是独立 XAML 缺陷。
- 调用改为 `out itemCount`；尺寸探测失败时不再把 `itemCount == 0` 当成硬失败（PDH 第一次调用可能只回写 buffer size）。
- `PDH_FMT_COUNTERVALUE` 改为 `LayoutKind.Explicit, Size = 16`，`doubleValue` 固定在 offset 8，对齐 x64 原生 union。
- 静态门禁新增 CS1620 / PDH union layout 回归检查。ASUS Engine、Broker、Recipe、PV/HOLTEK/ENE hash-lock 未改。
