# v3.4.13

Build: `20260922.winui3.19`

User log from the installed app:

```
source=OnLaunched
Microsoft.UI.Xaml.Markup.XamlParseException: XAML parsing failed.
at MainWindow.InitializeComponent()
at MainWindow..ctor()
```

v3.4.11/3.4.12 reached OnLaunched. App.xaml loaded. MainWindow.xaml LoadComponent then died on NavigationView + ThemeResource. WASDK 2.x unpackaged also emits `AssemblyName.pri` instead of `resources.pri`.

Fix:
- MainWindow shell is built in C#. XAML is an empty Grid. LoadComponent can no longer parse NavigationView.
- If NavigationView still throws, a 5-button bar is used. Pages still load in the Frame.
- Copy `WindowsGameRuntimeASUSSelfHealing.WinUI.pri` → `resources.pri` at build, publish, and startup.
- Log FileVersion / HRESULT / PRI list.

ASUS RepairCenter and PV/HOLTEK/ENE hash-lock unchanged.
