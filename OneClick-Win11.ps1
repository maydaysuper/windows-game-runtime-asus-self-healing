[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')]
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64',
    [switch]$NoLaunch,
    [switch]$ForceRestore
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Product = 'Windows Game Runtime / ASUS Armoury Self-Healing Center'
$Version = '4.2.0'
$Project = Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\WindowsGameRuntimeASUSSelfHealing.WinUI.csproj'
$PublishRoot = Join-Path $PSScriptRoot 'publish-win11-x64'
$LogRoot = Join-Path $PSScriptRoot 'BuildLogs'
$Desktop = [Environment]::GetFolderPath('Desktop')
$DesktopZip = Join-Path $Desktop ("Windows_Game_Runtime_ASUS_SelfHealing_Portable_v$Version`_win-x64.zip")
$StaticTests = Join-Path $PSScriptRoot 'Tests\Architecture.Tests.ps1'
$BuildStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RestoreLog = Join-Path $LogRoot ("Restore_{0}.log" -f $BuildStamp)
$RestoreBinLog = Join-Path $LogRoot ("Restore_{0}.binlog" -f $BuildStamp)
$PublishLog = Join-Path $LogRoot ("Publish_{0}.log" -f $BuildStamp)
$PublishBinLog = Join-Path $LogRoot ("Publish_{0}.binlog" -f $BuildStamp)
$LocalDotNetRoot = if($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'WindowsGameRuntimeASUSSelfHealing\dotnet10' } else { Join-Path $PSScriptRoot '.dotnet10' }

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$LogPath = Join-Path $LogRoot ("WinUI3_OneClick_{0}.log" -f $BuildStamp)

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ('==> ' + $Text) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host ('[PASS] ' + $Text) -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host ('[WARN] ' + $Text) -ForegroundColor Yellow
}

function Fail {
    param([string]$Text)
    Write-Host ('[FAIL] ' + $Text) -ForegroundColor Red
    throw $Text
}

function Get-DotNetCandidatePaths {
    $candidates = @(
        (Join-Path $LocalDotNetRoot 'dotnet.exe'),
        (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'dotnet\dotnet.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe')
    )

    $cmd = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if($cmd -and $cmd.Source) { $candidates += [string]$cmd.Source }

    return @($candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -Unique)
}

function Refresh-DotNetPath {
    foreach($exe in @(Get-DotNetCandidatePaths)) {
        $dir = Split-Path -Parent $exe
        if($dir -and (($env:Path -split ';') -notcontains $dir)) {
            $env:Path = $dir + ';' + $env:Path
        }
        if($exe -eq (Join-Path $LocalDotNetRoot 'dotnet.exe')) {
            $env:DOTNET_ROOT = $LocalDotNetRoot
        }
    }
}

function Get-DotNet10Sdk {
    Refresh-DotNetPath

    foreach($exe in @(Get-DotNetCandidatePaths)) {
        $versions = @()
        try { $versions = @(& $exe --list-sdks 2>$null) } catch {}

        foreach($line in $versions) {
            if($line -match '^\s*(?<v>10\.\d+\.\d+[^ ]*)\s+\[') {
                return [PSCustomObject]@{
                    Path = [string]$exe
                    Version = [string]$matches['v']
                }
            }
        }
    }
    return $null
}

function Download-MicrosoftDotNetInstallScript {
    $uri = 'https://dot.net/v1/dotnet-install.ps1'
    $installer = Join-Path $LogRoot 'dotnet-install.ps1'

    Write-Host '正在下载 Microsoft 官方 dotnet-install.ps1 ...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $installer -TimeoutSec 120
    } catch {
        Write-Warn ("Invoke-WebRequest 下载失败：{0}" -f $_.Exception.Message)
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if(-not $curl) {
            throw '无法下载 Microsoft dotnet-install.ps1，且系统未检测到 curl.exe。请检查网络/代理后重试。'
        }

        & $curl.Source -fL --retry 3 --connect-timeout 20 --output $installer $uri
        if($LASTEXITCODE -ne 0) {
            throw ("curl 下载 Microsoft dotnet-install.ps1 失败，ExitCode={0}" -f $LASTEXITCODE)
        }
    }

    if(-not (Test-Path -LiteralPath $installer)) {
        throw 'Microsoft dotnet-install.ps1 下载完成后文件不存在。'
    }
    $length = (Get-Item -LiteralPath $installer).Length
    if($length -lt 10000) {
        throw ("Microsoft dotnet-install.ps1 文件异常过小：{0} bytes" -f $length)
    }
    return $installer
}

function Install-DotNet10SdkLocal {
    Write-Step '切换到 Microsoft 官方 dotnet-install.ps1 本地 SDK 安装'
    Write-Host ("目标目录：{0}" -f $LocalDotNetRoot)
    Write-Host '该方式不需要修改系统 PATH，也不需要重新登录 Windows。'

    New-Item -ItemType Directory -Path $LocalDotNetRoot -Force | Out-Null
    $installer = Download-MicrosoftDotNetInstallScript

    $installArgs = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass',
        '-File',$installer,
        '-Channel','10.0',
        '-Quality','GA',
        '-Architecture','x64',
        '-InstallDir',$LocalDotNetRoot,
        '-NoPath'
    )
    & powershell.exe @installArgs
    $rc = $LASTEXITCODE
    if($rc -ne 0) {
        throw ("Microsoft dotnet-install.ps1 安装 .NET 10 SDK 失败，ExitCode={0}" -f $rc)
    }

    $env:DOTNET_ROOT = $LocalDotNetRoot
    if(($env:Path -split ';') -notcontains $LocalDotNetRoot) {
        $env:Path = $LocalDotNetRoot + ';' + $env:Path
    }

    $sdk = Get-DotNet10Sdk
    if(-not $sdk) {
        throw ("Microsoft dotnet-install.ps1 已结束，但 {0} 中仍未检测到 .NET 10 SDK。" -f $LocalDotNetRoot)
    }

    Write-Ok (".NET 10 SDK 本地工具缓存已就绪：{0} ({1})" -f $sdk.Version,$sdk.Path)
    return $sdk
}

function Install-DotNet10Sdk {
    Write-Step '未检测到 .NET 10 SDK，准备自动安装 Microsoft 官方 SDK'

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if($winget) {
        Write-Host '首选路径：WinGet / Microsoft.DotNet.SDK.10'
        Write-Host '先刷新 winget source，避免 0x8A15000F（source data missing）导致假失败。'

        & $winget.Source source update --name winget --disable-interactivity
        $sourceRc = $LASTEXITCODE
        $tryWingetInstall = $true
        if($sourceRc -eq -1978335217) {
            Write-Warn 'winget source update 返回 0x8A15000F / SOURCE_DATA_MISSING。跳过重复的 WinGet install，直接切换 Microsoft 官方安装脚本。'
            $tryWingetInstall = $false
        } elseif($sourceRc -ne 0) {
            Write-Warn ("winget source update 返回代码 {0}；仍尝试一次安装，失败后自动切换官方安装脚本。" -f $sourceRc)
        }

        if($tryWingetInstall) {
            & $winget.Source install --id Microsoft.DotNet.SDK.10 --exact --source winget `
                --accept-package-agreements --accept-source-agreements --silent --disable-interactivity

            $rc = $LASTEXITCODE
            if($rc -eq -1978335217) {
                Write-Warn 'winget 返回 0x8A15000F / SOURCE_DATA_MISSING。将自动绕过 WinGet source，改用 Microsoft 官方 dotnet-install.ps1。'
            } elseif($rc -ne 0) {
                Write-Warn ("winget 安装返回代码 {0}。将重新检测 SDK，仍不可用时自动回退。" -f $rc)
            }

            Start-Sleep -Seconds 2
            Refresh-DotNetPath
            $sdk = Get-DotNet10Sdk
            if($sdk) {
                Write-Ok (".NET 10 SDK 已通过 WinGet 就绪：{0} ({1})" -f $sdk.Version,$sdk.Path)
                return $sdk
            }
        }
    } else {
        Write-Warn '未检测到 winget / App Installer；直接使用 Microsoft 官方 dotnet-install.ps1。'
    }

    return (Install-DotNet10SdkLocal)
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Title,
        [string]$DiagnosticLog
    )

    Write-Step $Title
    Write-Host ($FilePath + ' ' + ($Arguments -join ' '))
    if($DiagnosticLog) { Write-Host ("详细 MSBuild 日志：{0}" -f $DiagnosticLog) -ForegroundColor DarkGray }
    & $FilePath @Arguments
    if($LASTEXITCODE -ne 0) {
        if($DiagnosticLog) {
            throw ("{0} 失败，ExitCode={1}。详细日志：{2}" -f $Title,$LASTEXITCODE,$DiagnosticLog)
        }
        throw ("{0} 失败，ExitCode={1}" -f $Title,$LASTEXITCODE)
    }
}

$transcriptStarted = $false
try {
    try {
        Start-Transcript -Path $LogPath -Force | Out-Null
        $transcriptStarted = $true
    } catch {}

    Write-Host ''
    Write-Host '================================================================' -ForegroundColor DarkCyan
    Write-Host " $Product - WPF v$Version" -ForegroundColor White
    Write-Host ' Windows 11 x64 一键构建 / 发布 / 启动' -ForegroundColor White
    Write-Host '================================================================' -ForegroundColor DarkCyan

    Write-Step '检查 Windows 11 与 CPU 架构'
    if($env:OS -ne 'Windows_NT') { Fail 'This WPF app can only be built on Windows.' }

    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $buildNumber = 0
    [void][int]::TryParse([string]$cv.CurrentBuildNumber,[ref]$buildNumber)
    if($buildNumber -lt 22000) {
        Fail ("当前 Windows Build={0}，这套一键包面向 Windows 11 Build 22000+。" -f $buildNumber)
    }
    if(-not [Environment]::Is64BitOperatingSystem) {
        Fail '当前不是 64 位 Windows，win-x64 构建不支持此系统。'
    }
    $arch = [string]$env:PROCESSOR_ARCHITECTURE
    if($arch -ne 'AMD64') {
        Fail ("当前 CPU 架构={0}。本构建包当前发布 win-x64，请使用 x64 Windows 11。" -f $arch)
    }
    Write-Ok ("Windows 11 {0} / Build {1} / x64" -f $cv.DisplayVersion,$buildNumber)

    Write-Step '检查 WinUI 3 项目文件'
    if(-not (Test-Path -LiteralPath $Project)) { Fail ("项目文件不存在：{0}" -f $Project) }
    Write-Ok 'WinUI 3 项目文件存在'

    Write-Step '执行 PowerShell Parser / 架构 / Hash-Lock 静态测试'
    if(-not (Test-Path -LiteralPath $StaticTests)) { Fail ("静态测试脚本不存在：{0}" -f $StaticTests) }
    $StaticLog = Join-Path $LogRoot ("StaticTests_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $staticOutput = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $StaticTests 2>&1)
    $staticExit = $LASTEXITCODE
    $staticOutput | Set-Content -LiteralPath $StaticLog -Encoding UTF8
    foreach($line in $staticOutput){ Write-Host ([string]$line) }
    if($staticExit -ne 0) { Fail ("静态测试失败，ExitCode={0}；详细日志：{1}" -f $staticExit,$StaticLog) }
    Write-Ok ("静态测试全部通过；日志：{0}" -f $StaticLog)

    Write-Step '检查 .NET 10 SDK'
    $sdk = Get-DotNet10Sdk
    if(-not $sdk) { $sdk = Install-DotNet10Sdk }
    else { Write-Ok (".NET 10 SDK：{0}" -f $sdk.Version) }

    $dotnet = $sdk.Path
    if(-not $dotnet) { $dotnet = (Get-Command dotnet.exe -ErrorAction Stop).Source }

    Write-Step '记录 .NET / Windows 构建环境'
    & $dotnet --info

    Write-Host ''
    Write-Host '构建方式：.NET CLI + WPF + Microsoft.Data.Sqlite'
    Write-Host '不需要 Windows App SDK / WinUI，也不需要先安装 Visual Studio；首次构建需要联网恢复 NuGet 包。'

    Write-Step '清理旧 bin / obj / publish'
    $projectDir = Split-Path -Parent $Project
    foreach($name in @('bin','obj')) {
        Remove-Item -LiteralPath (Join-Path $projectDir $name) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $PublishRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $PublishRoot -Force | Out-Null
    Write-Ok '旧构建缓存已清理'

    $restoreArgs = @(
        'restore',$Project,
        '-r',$Runtime,
        '--nologo',
        '-p:Platform=x64',
        '-v:minimal',
        ("-flp:logfile={0};verbosity=normal" -f $RestoreLog),
        ("-bl:{0}" -f $RestoreBinLog)
    )
    if($ForceRestore) {
        $restoreArgs += '--force'
        $restoreArgs += '--no-cache'
    }
    Invoke-LoggedCommand -FilePath $dotnet -Arguments $restoreArgs -Title '恢复 WPF / Sqlite NuGet 依赖' -DiagnosticLog $RestoreLog

    $publishArgs = @(
        'publish',$Project,
        '-c',$Configuration,
        '-r',$Runtime,
        '-o',$PublishRoot,
        '--self-contained','true',
        '--no-restore',
        '--nologo',
        '-p:Platform=x64',
        '-p:SelfContained=true',
        '-p:PublishSingleFile=false',
        '-p:PublishTrimmed=false',
        '-p:PublishReadyToRun=false',
        '-v:minimal',
        ("-flp:logfile={0};verbosity=normal" -f $PublishLog),
        ("-bl:{0}" -f $PublishBinLog)
    )
    Invoke-LoggedCommand -FilePath $dotnet -Arguments $publishArgs -Title '发布 WPF 自包含运行目录' -DiagnosticLog $PublishLog

    Write-Step 'Materialize hash-locked Backend beside published EXE'
    $sourceBackend = Join-Path $PSScriptRoot 'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend'
    $backendDir = Join-Path $PublishRoot 'Backend'
    if(-not (Test-Path -LiteralPath $sourceBackend)) { Fail '源码 Backend 目录缺失，无法保持 ASUS hash-lock。' }
    New-Item -ItemType Directory -Path $backendDir -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceBackend -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $backendDir $_.Name) -Force
    }
    Write-Ok ("已将 {0} 个 hash-lock Backend 文件落到 publish 目录。" -f @(Get-ChildItem -LiteralPath $backendDir -File).Count)

    Write-Step '验证发布目录与主程序'
    $exe = Get-ChildItem -LiteralPath $PublishRoot -Filter '*.exe' -File |
        Where-Object { $_.Name -notmatch 'createdump|WindowsAppRuntimeInstall' } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if(-not $exe) { Fail 'dotnet publish 已结束，但 publish 目录没有找到主程序 EXE。' }

    $dlls = @(Get-ChildItem -LiteralPath $PublishRoot -Filter '*.dll' -File)
    if($dlls.Count -lt 8) {
        Fail ("publish 目录 DLL 过少（{0}），疑似又打成了 Single-file。WPF 原生运行库必须和 EXE 在同一目录，否则安装后无法打开。" -f $dlls.Count)
    }
    foreach($requiredDll in @('wpfgfx_cor3.dll','PresentationNative_cor3.dll','e_sqlite3.dll')) {
        if(-not (Test-Path -LiteralPath (Join-Path $PublishRoot $requiredDll))) {
            Fail ("publish 目录缺少 {0}。禁止继续打包。" -f $requiredDll)
        }
    }
    Write-Ok ("WPF 原生 DLL 已与 EXE 同目录（{0} 个 DLL）。" -f $dlls.Count)

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe.FullName).Hash.ToLowerInvariant()
    Write-Ok ("EXE：{0}" -f $exe.FullName)
    Write-Ok ("大小：{0:N1} MB" -f ($exe.Length/1MB))
    Write-Ok ("SHA256：{0}" -f $hash)

    Write-Step '组装用户包（启动器 + App 目录）并生成 Portable ZIP'
    $backendDir = Join-Path $PublishRoot 'Backend'
    if(-not (Test-Path -LiteralPath $backendDir)) {
        Fail 'publish 目录缺少 Backend。ASUS hash-lock 修复链不允许发布孤立 EXE。'
    }
    $releaseDir = Join-Path $PSScriptRoot 'artifacts\release'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build-Release.ps1') -PublishRoot $PublishRoot -ReleaseDir $releaseDir -SkipInstaller
    if($LASTEXITCODE -ne 0) { Fail 'Build-Release.ps1 组装用户包失败。' }
    $builtZip = Join-Path $releaseDir ("Windows_Game_Runtime_ASUS_SelfHealing_Portable_v{0}_win-x64.zip" -f $Version)
    if(-not (Test-Path -LiteralPath $builtZip)) { Fail '未生成 Portable ZIP。' }
    Remove-Item -LiteralPath $DesktopZip -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $builtZip -Destination $DesktopZip -Force
    $zipHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $DesktopZip).Hash.ToLowerInvariant()
    Write-Ok ("ZIP：{0}" -f $DesktopZip)
    Write-Ok ("ZIP SHA256：{0}" -f $zipHash)

    $launcher = Join-Path $PSScriptRoot 'artifacts\package\SelfHealingCenter.exe'
    Write-Host ''
    Write-Host '最终程序为 WPF self-contained。用户包只有启动器、使用说明和 App 目录。' -ForegroundColor DarkGray
    Write-Host '请双击 SelfHealingCenter.exe，不要单独运行 App 里的 EXE，也不要从开始菜单启动。' -ForegroundColor DarkGray

    if(-not $NoLaunch) {
        Write-Step '从用户包启动器打开自愈中心'
        if(-not (Test-Path -LiteralPath $launcher)) { Fail '用户包缺少 SelfHealingCenter.exe。' }
        Start-Process -FilePath $launcher -WorkingDirectory (Split-Path -Parent $launcher)
        Write-Ok '已启动。GUI 为普通权限；真正修复时才由 Elevated Broker 请求 UAC。'
    }

    Write-Host ''
    Write-Host '==================== 构建成功 ====================' -ForegroundColor Green
    Write-Host ("Publish 主程序：{0}" -f $exe.FullName) -ForegroundColor Green
    Write-Host ("EXE SHA256：{0}" -f $hash) -ForegroundColor Green
    Write-Host ("Portable ZIP：{0}" -f $DesktopZip) -ForegroundColor Green
    Write-Host ("ZIP SHA256：{0}" -f $zipHash) -ForegroundColor Green
    Write-Host ("构建日志：{0}" -f $LogPath) -ForegroundColor Green
    Write-Host ("Restore 日志：{0}" -f $RestoreLog) -ForegroundColor Green
    Write-Host ("Publish 日志：{0}" -f $PublishLog) -ForegroundColor Green
    Write-Host ("Publish BinLog：{0}" -f $PublishBinLog) -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host '==================== 构建失败 ====================' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host ("日志：{0}" -f $LogPath) -ForegroundColor Yellow
    Write-Host '如果失败，请优先发送 BuildLogs 里的 WinUI3_OneClick、Publish/Restore .log；必要时再附 .binlog。' -ForegroundColor Yellow
    exit 1
}
finally {
    if($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}
