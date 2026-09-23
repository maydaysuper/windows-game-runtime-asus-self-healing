#define MyAppName "奥创修复中心"
#define MyAppPublisher "maydaysuper"
#ifndef MyAppVersion
  #define MyAppVersion "4.6.3"
#endif
#ifndef SourceRoot
  #define SourceRoot "..\artifacts\package"
#endif
#ifndef OutputDir
  #define OutputDir "..\artifacts\installer"
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
DefaultDirName={localappdata}\Programs\WindowsGameRuntimeASUSSelfHealing
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
SetupIconFile=..\WindowsGameRuntimeASUSSelfHealing.WinUI\Assets\app.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "Upgrade-Legacy.ps1"; Flags: dontcopy
Source: "{#SourceRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Check: CanCreateDesktopShortcut

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\BuildLogs"
; User SQLite state is outside {app}:
;   %LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\State\state-v1.db
; Uninstall must not delete Transaction / Incident / Workflow / dump analysis history.

[Code]
function CanCreateDesktopShortcut: Boolean;
var
  Path: String;
  Shell, Link: Variant;
begin
  Path := ExpandConstant('{autodesktop}\奥创修复中心.lnk');
  Result := not FileExists(Path);
  if not Result then
  begin
    try
      Shell := CreateOleObject('WScript.Shell');
      Link := Shell.CreateShortcut(Path);
      Result := CompareText(Link.TargetPath, ExpandConstant('{app}\SelfHealingCenter.exe')) = 0;
    except
      Log('Preserving unreadable desktop shortcut: ' + Path);
      Result := False;
    end;
  end;
end;

function RunUpgradeHelper(const Mode: String): Boolean;
var
  Code: Integer;
  Params: String;
begin
  ExtractTemporaryFile('Upgrade-Legacy.ps1');
  Params := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{tmp}\Upgrade-Legacy.ps1') + '" -Mode ' + Mode +
    ' -InstallRoot "' + ExpandConstant('{app}') + '" -ExpectedVersion "{#MyAppVersion}"' +
    ' -LogPath "' + ExpandConstant('{tmp}\legacy-upgrade.log') + '"';
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := Result and (Code = 0);
  Log('Legacy upgrade helper ' + Mode + ': exit ' + IntToStr(Code));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not RunUpgradeHelper('Clean') then
    Result := '无法安全清理旧版运行环境。请关闭旧版程序后重试。升级日志：' +
      ExpandConstant('{tmp}\legacy-upgrade.log');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    if not RunUpgradeHelper('Verify') then
      RaiseException('安装验证失败：启动器或 App 主程序缺失、版本不匹配。请重新运行安装程序。');
end;
