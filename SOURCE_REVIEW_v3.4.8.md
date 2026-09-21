# Source Review v3.4.8

## Scope
v3.4.8 unblocks `dotnet publish` on Windows 11 x64 / .NET 10 after v3.4.7 failed at `XamlPreCompile` with CS1620.

## Compile failure reconstructed
Publish log `Publish_20260921_224719.log` contains:

```
GpuMemoryTelemetryService.cs(184,98): error CS1620: 参数 4 必须与关键字“out”一起传递
GpuMemoryTelemetryService.cs(190,98): error CS1620: 参数 4 必须与关键字“out”一起传递
```

`PdhGetFormattedCounterArrayW` is declared as `out uint itemCount`. The two call sites passed `ref itemCount`. The XAML `WMC9999` null-ref is a cascade from `_OnXamlPreCompileError` after C# precompile failed.

## Fix
- Call sites now pass `out itemCount`.
- Size-query call no longer treats a zero `itemCount` as fatal; PDH may only fill the required buffer size on the first call.
- `PDH_FMT_COUNTERVALUE` uses explicit 16-byte x64 union layout.

## Integrity
Engine/Broker/UiBridge/Recipe/Atomic Policy/GPU reader/safe repair/PV/HOLTEK/ENE hashes are unchanged. Version metadata and the C# PDH helper are the only functional source changes.
