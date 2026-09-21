# Source Review v3.4.13

startup-crash.log from the installed copy:

- host = %LOCALAPPDATA%\Programs\WindowsGameRuntimeASUSSelfHealing
- source = OnLaunched
- MainWindow.InitializeComponent → LoadComponent → XamlParseException

App.xaml already parsed, so WinUI and the app PRI work. MainWindow.xaml content (NavigationView, ThemeResource, ProgressRing) does not.

v3.4.13 removes those elements from MainWindow.xaml and builds the same 5-item shell in code. Also copies AssemblyName.pri to resources.pri for WASDK 2.x unpackaged MRT.
