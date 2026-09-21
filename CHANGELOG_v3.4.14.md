# v3.4.14

Build: `20260922.winui3.20`

v3.4.13 still flash-closed because templated WinUI controls (`NavigationView`, `InfoBar`, `ProgressRing`, `XamlControlsResources` generic.xaml) FailFast in native code on unpackaged WASDK 2.x. Managed try/catch cannot catch that.

- MainWindow is C# only (no XAML, no NavigationView). Five primary buttons remain.
- InfoBar replaced by primitive `StatusBanner` (Grid).
- ThemeResource removed from pages; App.xaml has CardStrokeBrush / CardFillBrush.
- App.xaml no longer merges XamlControlsResources.
- ASUS hash-lock unchanged.
