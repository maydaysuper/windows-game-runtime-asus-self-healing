# v3.4.6

- Fixed the real WinUI XAML compiler failures reported by `Publish_20260921_214519.log`.
- Replaced invalid direct `TextBox.VerticalScrollBarVisibility` / `HorizontalScrollBarVisibility` attributes with WinUI 3 attached properties `ScrollViewer.VerticalScrollBarVisibility` / `ScrollViewer.HorizontalScrollBarVisibility`.
- Added regression gates so these UWP/WPF-style TextBox members cannot re-enter the source.
- Added formal Windows release packaging: portable self-contained build + single-file Inno Setup installer EXE.
- Installer is per-user and does not require elevation to install; repair actions still elevate only through the existing Broker.
- ASUS RepairCenter, Broker policy, PV/HOLTEK/ENE legacy adapters, GPU/ReBAR diagnostics and safe-repair backend remain unchanged.
