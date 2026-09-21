# Source Review v3.4.12

User screenshot after v3.4.11: StartupGuard dialog
`XamlParseException: XAML parsing failed.`
Log: `%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\Logs\startup-crash.log`

v3.4.11 got past WASDK bootstrap FailFast. ProbeNativeRuntime passed (native DLLs present). Then `new MainWindow()` → `InitializeComponent()` parsed NavigationView / ThemeResource without WinUI generic.xaml.

`App.xaml` had custom brushes only. Official WinUI 3 template always merges:

```xml
<XamlControlsResources xmlns="using:Microsoft.UI.Xaml.Controls" />
```

On a developer box with Windows App Runtime installed, bootstrap registered those resources from the framework package, so the missing merge was hidden.

Fix: merge XamlControlsResources, wrap accent Color as Brush, enable undocked reg-free WinRT, keep bootstrap off.
