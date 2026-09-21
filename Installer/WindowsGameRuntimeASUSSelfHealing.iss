#define MyAppName "Windows Game Runtime - ASUS Armoury Self-Healing Center"
#define MyAppPublisher "maydaysuper"
#ifndef MyAppVersion
  #define MyAppVersion "4.1.3"
#endif
#ifndef SourceRoot
  #define SourceRoot "..\\artifacts\\publish"
#endif
#ifndef OutputDir
  #define OutputDir "..\\artifacts\\installer"
#endif
#define MyAppExeName "WindowsGameRuntimeASUSSelfHealing.WinUI.exe"

[Setup]
AppId={{8E7A18D4-0B8B-4F8C-A094-9B2026A57A41}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\\Programs\\WindowsGameRuntimeASUSSelfHealing
DefaultGroupName={#MyAppName}
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
UsePreviousGroup=yes
SetupIconFile=..\\WindowsGameRuntimeASUSSelfHealing.WinUI\\Assets\\app.ico
UninstallDisplayIcon={app}\\{#MyAppExeName}

[Files]
Source: "{#SourceRoot}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\\BuildLogs"
; User SQLite state is outside {app}:
;   %LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\State\state-v1.db
; Uninstall must not delete Transaction / Incident / Workflow / dump analysis history.
