# Source Review v3.4.11

User screenshot: `WindowsGameRuntimeASUSSelfHealing.WinUI.exe - Fail Fast Exception`
「发生了快速异常检测失败。将不会调用异常处理程序，并且进程将立即终止。」

That dialog is `Environment.FailFast` from the Windows App SDK bootstrap **module initializer**, which runs before `Program.Main`. Custom Main / StartupGuard never execute.

v3.4.10 still had:

```xml
<WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
<WindowsAppSdkBootstrapInitialize>true</WindowsAppSdkBootstrapInitialize>
```

Microsoft docs: bootstrap auto-init is for **framework-dependent unpackaged** apps. Self-contained apps do not use the shared Windows App Runtime MSIX, so bootstrap should be false.

The screenshot folder also showed `Microsoft.Windows.SDK.NET.dll` / `WinRT.Runtime.dll` without `Microsoft.ui.xaml.dll` immediately above it. That is either a local framework-dependent publish or an incomplete copy. Official Setup must still be a folder deploy with native DLLs beside the EXE.

Fix:
- `WindowsAppSdkBootstrapInitialize=false`
- `WindowsAppSdkDeploymentManagerInitialize=false`
- keep `WindowsAppSDKSelfContained=true` + `PublishSingleFile=false`
- CI/OneClick pass the same properties on the command line
- hash-lock files untouched
