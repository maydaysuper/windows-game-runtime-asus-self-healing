#define MyAppName "奥创修复中心"
#define MyAppPublisher "maydaysuper"
#ifndef MyAppVersion
  #define MyAppVersion "4.5.2"
#endif
#ifndef SourceRoot
  #define SourceRoot "..\\artifacts\\package"
#endif
#ifndef OutputDir
  #define OutputDir "..\\artifacts\\installer"
#endif
#define MyAppExeName "SelfHealingCenter.exe"
; Inner WPF host (do not shortcut this; launcher sets WorkingDir to App\):
; WindowsGameRuntimeASUSSelfHealing.WinUI.exe

[Setup]
AppId={{8E7A18D4-0B8B-4F8C-A094-9B2026A57A41}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}
UninstallDisplayName={#MyAppName}
DefaultDirName={localappdata}\\Programs\\WindowsGameRuntimeASUSSelfHealing
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
MinVersion=10.0.22000
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Windows_Game_Runtime_ASUS_SelfHealing_Setup_v{#MyAppVersion}_x64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
Uninstallable=yes
UsePreviousAppDir=yes
SetupIconFile=..\\WindowsGameRuntimeASUSSelfHealing.WinUI\\Assets\\app.ico
UninstallDisplayIcon={app}\\{#MyAppExeName}

[Files]
Source: "{#SourceRoot}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\\BuildLogs"
; User SQLite state is outside {app}:
;   %LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\State\state-v1.db
; Uninstall must not delete Transaction / Incident / Workflow / dump analysis history.

[InstallDelete]
Type: files; Name: "{autodesktop}\\自愈中心.lnk"
