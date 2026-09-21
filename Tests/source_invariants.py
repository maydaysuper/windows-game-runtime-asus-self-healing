from __future__ import annotations
from pathlib import Path
import base64, hashlib, json, re, sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
PROJ=ROOT/'WindowsGameRuntimeASUSSelfHealing.WinUI'
BACK=PROJ/'Backend'
passes=[]; failures=[]
def ok(msg): passes.append(msg)
def fail(msg): failures.append(msg)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

# XML/XAML well-formed
for p in sorted(list(PROJ.rglob('*.xaml'))+list(PROJ.rglob('*.csproj'))):
    try: ET.parse(p); ok('XML '+str(p.relative_to(ROOT)))
    except Exception as e: fail(f'XML {p}: {e}')

# XAML event handlers have C# methods (basic static binding check)
for xaml in PROJ.rglob('*.xaml'):
    cs=Path(str(xaml)+'.cs')
    if not cs.exists(): continue
    x=xaml.read_text(encoding='utf-8')
    c=cs.read_text(encoding='utf-8')
    for attr,name in re.findall(r'\b(Click|Loaded|SelectionChanged)="([A-Za-z_][A-Za-z0-9_]*)"',x):
        if re.search(r'\b'+re.escape(name)+r'\s*\(',c): ok(f'event {xaml.name}:{name}')
        else: fail(f'missing handler {xaml.name}:{attr}={name}')

# BuildInfo hash chain
bj=json.loads((BACK/'BuildInfo.json').read_text(encoding='utf-8'))
psd=(BACK/'BuildInfo.psd1').read_text(encoding='utf-8')
expected_files={
 'EngineSHA256':'RepairCenter.ps1','BrokerSHA256':'ElevatedBroker.ps1','BootstrapSHA256':'Bootstrap.ps1',
 'UiBridgeSHA256':'UiBridge.ps1','EventReaderSHA256':'IncrementalEventReader.ps1',
 'GpuDiagnosticsReaderSHA256':'GpuDiagnosticsReader.ps1','GpuSafeRepairSHA256':'GpuSafeRepair.ps1',
 'AtomicPolicyExecutorSHA256':'AtomicPolicyExecutor.ps1','RecipeCatalogSHA256':'RecipeCatalog.psd1'}
for key,name in expected_files.items():
    actual=sha(BACK/name)
    if actual==bj[key]: ok('hash '+name)
    else: fail(f'hash {name} actual={actual} expected={bj[key]}')
if sha(BACK/'BuildInfo.psd1')==bj['BuildInfoSHA256']: ok('hash BuildInfo.psd1')
else: fail('BuildInfo.psd1 hash mismatch')
if f"Version = '{bj['Version']}'" in psd: ok('version '+bj['Version'])
else: fail('version mismatch')
if "StateSchemaVersion = 3" in psd and bj.get('StateSchemaVersion')==3: ok('state schema 3 metadata')
else: fail('state schema metadata mismatch')

# Immutable legacy adapter locks + embedded payloads
lock=json.loads((ROOT/'LEGACY_ADAPTER_LOCK.json').read_text(encoding='utf-8'))
engine=(BACK/'RepairCenter.ps1').read_text(encoding='utf-8')
for key,var in [('PV','EmbeddedPV'),('HOLTEK','EmbeddedHoltek'),('ENE','EmbeddedENE')]:
    ent=lock['Modules'][key]
    expected=ent['SHA256'].lower()
    if sha(ROOT/ent['File'])==expected: ok('legacy source '+key)
    else: fail('legacy source drift '+key)
    m=re.search(r'^\s*'+re.escape(key)+r"='([0-9a-f]{64})'",engine,re.M)
    if m and m.group(1).lower()==expected: ok('engine lock '+key)
    else: fail('engine lock drift '+key)
    m=re.search(r"\$"+re.escape(var)+r"\s*=\s*'([^']+)'",engine,re.S)
    if not m: fail('embedded payload missing '+key); continue
    try: embedded=hashlib.sha256(base64.b64decode(m.group(1),validate=True)).hexdigest()
    except Exception as e: fail(f'embedded payload invalid {key}: {e}'); continue
    if embedded==expected: ok('embedded payload '+key)
    else: fail('embedded payload drift '+key)

# Primary navigation exactly simplified
main=(PROJ/'MainWindow.xaml').read_text(encoding='utf-8')
tags=re.findall(r'\bTag="([a-z]+)"',main)
if tags==['overview','asus','runtime','crash','reports']: ok('primary navigation exactly 5 simplified entries')
else: fail('primary navigation tags='+repr(tags))

# Async discipline
bad=[]
for p in PROJ.rglob('*.cs'):
    text=p.read_text(encoding='utf-8')
    if re.search(r'\.Result\b|\.Wait\s*\(|GetAwaiter\(\)\.GetResult\(\)',text): bad.append(str(p.relative_to(ROOT)))
if not bad: ok('no sync-over-async patterns')
else: fail('sync-over-async '+','.join(bad))

# v3.4 architecture invariants
state=(PROJ/'Services'/'StateStoreService.cs').read_text(encoding='utf-8')
dump=(PROJ/'Services'/'DumpAnalysisService.cs').read_text(encoding='utf-8')
reports=(PROJ/'Services'/'ReportService.cs').read_text(encoding='utf-8')
resources=(PROJ/'Services'/'AdaptiveResourceGovernor.cs').read_text(encoding='utf-8')
backend=(PROJ/'Services'/'BackendService.cs').read_text(encoding='utf-8')
for cond,msg in [
 ('private const int SchemaVersion = 3;' in state and 'CREATE TABLE IF NOT EXISTS dump_analyses' in state,'SQLite schema 3 dump table'),
 ('wal_autocheckpoint=256' in state and 'journal_size_limit=4194304' in state and 'SqliteCacheMode.Private' in state,'bounded SQLite WAL/private cache'),
 ('MemoryMappedFile' in dump and 'MiniDumpReadDumpStream' in dump,'memory-mapped DbgHelp dump analysis'),
 (all(x in reports for x in ['GenerateSystemHealthReportAsync','GenerateRepairReportAsync','CreateDumpAnalysisReportAsync','CreateGpuDiagnosisReportAsync']),'unified report service'),
 ('Environment.ProcessorCount' in resources and 'TotalAvailableMemoryBytes' in resources and 'SemaphoreSlim' in resources,'adaptive CPU/memory resource governor'),
 ('EnterBackgroundWorkAsync' in backend and 'TuneChildProcess' in backend,'backend uses adaptive governor'),
]:
    ok(msg) if cond else fail(msg)

# v3.4 low-resource UI/lifetime invariants
maincs=(PROJ/'MainWindow.xaml.cs').read_text(encoding='utf-8')
appcs=(PROJ/'App.xaml.cs').read_text(encoding='utf-8')
overview=(PROJ/'Pages'/'OverviewPage.xaml.cs').read_text(encoding='utf-8')
main_pages=[PROJ/'Pages'/x for x in ['OverviewPage.xaml.cs','SafetyPage.xaml.cs','RuntimePage.xaml.cs','CrashPage.xaml.cs','ReportsPage.xaml.cs']]
if 'NavigateTag' in maincs and 'overview' in maincs: ok('WPF shell navigates the five primary pages')
else: fail('WPF main navigation missing')
if '_pages' in maincs and 'TryGetValue' in maincs: ok('primary page instance cache')
else: fail('primary page instance cache missing')
if 'BuildShellInCode' in maincs: ok('WPF shell has code-built fallback')
else: fail('code-built WPF shell fallback missing')
if all('InitializeComponent' in x.read_text(encoding='utf-8') for x in main_pages): ok('main pages keep generated InitializeComponent')
else: fail('main page partials drifted')
if 'GC.Collect' not in overview and 'RequestIdleCollection' not in resources: ok('no forced GC on interactive path')
else: fail('forced GC reintroduced')
if 'Services.Dispose();' in appcs: ok('application closes service lifetime explicitly')
else: fail('service lifetime cleanup missing')

# Crash/GPU read-only telemetry must remain before engine import in UiBridge
bridge=(BACK/'UiBridge.ps1').read_text(encoding='utf-8')
b=bridge.find('. $EnginePath -LibraryMode')
for marker in ["if($Action -eq 'CRASH_DELTA')","if($Action -eq 'GPU_DIAGNOSTICS')"]:
    a=bridge.find(marker)
    if a>=0 and b>=0 and a<b: ok(marker+' bypasses RepairCenter')
    else: fail(marker+' isolation drift')

# dangerous automation remains off in RecipeCatalog text
recipe=(BACK/'RecipeCatalog.psd1').read_text(encoding='utf-8')
if re.search(r'AutomaticDDU\s*=\s*\$false',recipe,re.I) and re.search(r'BlindDriverRemoval\s*=\s*\$false',recipe,re.I) and 'DIAGNOSE_ONLY' in recipe: ok('dangerous automation policy remains disabled')
else: fail('dangerous automation policy drift')

# GPU/ReBAR root-cause diagnostics and safe-remediation boundary.
gpu_diag=(PROJ/'Services'/'GpuDiagnosticsService.cs').read_text(encoding='utf-8')
gpu_mem=(PROJ/'Services'/'GpuMemoryTelemetryService.cs').read_text(encoding='utf-8')
gpu_reader=(BACK/'GpuDiagnosticsReader.ps1').read_text(encoding='utf-8')
gpu_repair=(BACK/'GpuSafeRepair.ps1').read_text(encoding='utf-8')
crash_page=(PROJ/'Pages'/'CrashPage.xaml.cs').read_text(encoding='utf-8')
for token in ['REBAR_COMPATIBILITY_SUSPECTED','TRUE_VRAM_PRESSURE','DRIVER_TDR','PCIE_LINK','POWER_DELIVERY_SUSPECTED','EVIDENCE_INSUFFICIENT']:
    ok('GPU classifier '+token) if token in gpu_diag else fail('GPU classifier missing '+token)
if all(x in gpu_mem for x in ['PdhAddEnglishCounterW','GPU Adapter Memory(*)','Dedicated Usage','Shared Usage','CreateDXGIFactory1']): ok('GPU memory uses localized-safe PDH English counters + DXGI')
else: fail('GPU memory telemetry native counter/DXGI path incomplete')
if 'PdhGetFormattedCounterArrayW' in gpu_mem and 'out uint itemCount' in gpu_mem and not re.search(r'PdhGetFormattedCounterArrayW\([^;]*ref itemCount', gpu_mem): ok('PDH formatted counter array uses out itemCount (CS1620-safe)')
else: fail('PdhGetFormattedCounterArrayW out/ref mismatch (CS1620)')
if 'LayoutKind.Explicit, Size = 16' in gpu_mem and re.search(r'FieldOffset\(8\)\]\s*public double DoubleValue', gpu_mem): ok('PDH_FMT_COUNTERVALUE uses explicit x64 union layout')
else: fail('PDH_FMT_COUNTERVALUE layout is not CS/x64-safe')
if all(x in gpu_reader for x in ['nvlddmkm','WHEA-Logger','Kernel-Power','LiveKernelReports','RebarState','TdrOverrides']): ok('GPU evidence reader covers ReBAR/TDR/WHEA/power/livekernel')
else: fail('GPU evidence reader incomplete')
if all(x in gpu_reader for x in ['DisplayTdrTimesUtc','VendorDriverTimesUtc','WheaPcieTimesUtc','AbruptPowerLossTimesUtc']) and all(x in gpu_diag for x in ['CountNearPairs','TimeSpan.FromMinutes(10)','TimeSpan.FromMinutes(30)']): ok('GPU root-cause classifier uses bounded temporal correlation')
else: fail('GPU temporal-correlation guard missing')
if all(x in gpu_repair for x in ['GpuCacheBackups','/scan-devices','TdrRegistryWrites=$false','AutomaticDDU=$false','DriverRemoval=$false','BiosWrites=$false']): ok('GPU safe repair is rollback-oriented and non-destructive')
else: fail('GPU safe repair safety contract incomplete')
if 'GPU_SAFE_REPAIR' in crash_page and 'RunGpuDiagnosisAsync' in crash_page: ok('GPU diagnosis/safe repair user accessible')
else: fail('GPU diagnosis UI path missing')
if all(x in gpu_diag for x in ['LiveKernelReports','_dumpAnalysis.AnalyzeAsync','SaveDumpAnalysisAsync']): ok('GPU diagnosis auto-analyzes newest local LiveKernel dump best-effort')
else: fail('GPU LiveKernel dump auto-analysis path missing')

# WinUI 3 XAML compiler compatibility + installer release contract.
invalid_scroll=[]
for xaml in PROJ.rglob('*.xaml'):
    raw=xaml.read_text(encoding='utf-8')
    if re.search(r'(?<!ScrollViewer\.)(?:Horizontal|Vertical)ScrollBarVisibility\s*=',raw):
        invalid_scroll.append(str(xaml.relative_to(ROOT)))
if not invalid_scroll: ok('WinUI TextBox scrollbar members use ScrollViewer attached properties')
else: fail('invalid direct TextBox ScrollBarVisibility members: '+','.join(invalid_scroll))
invalid_panel_padding=[]
for xaml in PROJ.rglob('*.xaml'):
    raw=xaml.read_text(encoding='utf-8')
    if re.search(r'<(?:Grid|StackPanel|DockPanel|WrapPanel|Canvas|UniformGrid|Page)\b[^>]*\sPadding\s*=',raw):
        invalid_panel_padding.append(str(xaml.relative_to(ROOT)))
if not invalid_panel_padding: ok('WPF panels do not use WinUI Padding')
else: fail('WPF-invalid Padding on Grid/StackPanel/Page: '+','.join(invalid_panel_padding))
installer=ROOT/'Installer'/'WindowsGameRuntimeASUSSelfHealing.iss'
if installer.exists():
    raw=installer.read_text(encoding='utf-8')
    if all(x in raw for x in ['PrivilegesRequired=lowest','MinVersion=10.0.22000','ArchitecturesAllowed=x64compatible','recursesubdirs','WindowsGameRuntimeASUSSelfHealing.WinUI.exe','WorkingDir: "{app}"','SelfHealingCenter.exe','autodesktop']): ok('Setup installer packages complete Win11 x64 runtime per-user')
    else: fail('installer contract drift')
    if 'autoprograms' in raw: fail('Setup must not create a Start Menu shortcut')
    else: ok('Setup does not create a Start Menu shortcut')
    if '[Tasks]' in raw or 'desktopicon' in raw: fail('desktop shortcut must be unconditional, not a Setup task')
    else: ok('desktop shortcut is unconditional')
else: fail('installer definition missing')
verify_payload=(ROOT/'Installer'/'Verify-PublishPayload.ps1').read_text(encoding='utf-8-sig')
build_installer=(ROOT/'Installer'/'Build-Installer.ps1').read_text(encoding='utf-8-sig')
build_release=(ROOT/'Build-Release.ps1').read_text(encoding='utf-8-sig')
if all(x in verify_payload for x in ['Assert-PeX64','LegacyAdapterHashes','CapabilityBaselineSHA256','PAYLOAD_SHA256.txt','wpfgfx_cor3.dll','PublishSingleFile is forbidden']): ok('published payload verifier covers x64 + backend + legacy hash chain')
else: fail('published payload verifier incomplete')
if all(x in build_installer for x in ['Verify-PublishPayload.ps1','Inno Setup 7','Inno Setup 6','.sha256.txt','Select-Object -First 1','SelfHealingCenter.exe','App\\WindowsGameRuntimeASUSSelfHealing.WinUI.exe']) and '$isccCandidates[0]' not in build_installer: ok('installer builder verifies payload and supports Inno 7/6')
else: fail('installer builder contract incomplete')
if all(x in build_release for x in ['Windows_Game_Runtime_ASUS_SelfHealing_Portable_v','Build-Installer.ps1','RELEASE_SHA256.txt','RELEASE_MANIFEST.json','SelfHealingCenter.exe','Join-Path $package App','Build-DesktopLauncher']): ok('release builder emits portable + setup + manifests')
else: fail('release builder contract incomplete')
workflow=(ROOT/'.github'/'workflows'/'windows-ci.yml').read_text(encoding='utf-8')
if all(x in workflow for x in ['Verify published payload trust chain','JRSoftware.InnoSetup.7','Build-Release.ps1','artifacts/release/*','-p:Platform=$env:PLATFORM','softprops/action-gh-release','Show-MsBuildErrors','contents: write','Materialize hash-locked Backend','PublishSingleFile=false','wpfgfx_cor3.dll']): ok('Windows CI emits verified installer + portable release artifacts')
else: fail('Windows CI release artifact pipeline incomplete')
attrs=(ROOT/'.gitattributes').read_text(encoding='utf-8')
if 'WindowsGameRuntimeASUSSelfHealing.WinUI/Backend/** -text' in attrs and 'LEGACY_ADAPTER_LOCK.json -text' in attrs: ok('gitattributes keeps Backend/legacy hash-lock files byte-identical')
else: fail('gitattributes Backend hash-lock -text missing')

# Current stable technology baseline and central package management
packages=(ROOT/'Directory.Packages.props').read_text(encoding='utf-8')
buildprops=(ROOT/'Directory.Build.props').read_text(encoding='utf-8')
csproj=(PROJ/'WindowsGameRuntimeASUSSelfHealing.WinUI.csproj').read_text(encoding='utf-8')
for token,msg in [
    ('ManagePackageVersionsCentrally>true','NuGet central package management enabled'),
    ('Microsoft.Data.Sqlite" Version="10.0.12','Microsoft.Data.Sqlite 10.0.12 pinned')]:
    ok(msg) if token in packages else fail(msg)
if 'Microsoft.WindowsAppSDK' in packages: fail('Windows App SDK must not be referenced after WPF recast')
else: ok('Windows App SDK removed from central packages')
for token,msg in [
    ('<LangVersion>14.0</LangVersion>','C# 14 compiler baseline'),
    ('<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>','code style analysis in build'),
    ('<NuGetAudit>true</NuGetAudit>','NuGet audit enabled'),
    ('<NuGetAuditMode>all</NuGetAuditMode>','NuGet audit includes transitive packages')]:
    ok(msg) if token in buildprops else fail(msg)
if '<PackageReference Include="Microsoft.Data.Sqlite" />' in csproj and '<UseWPF>true</UseWPF>' in csproj: ok('project is WPF + centrally pinned Sqlite')
else: fail('project is not WPF / Sqlite')
if 'Using Remove="System.Windows.Shapes"' in csproj: ok('WPF Shapes.Path does not shadow System.IO.Path')
else: fail('csproj must remove System.Windows.Shapes so System.IO.Path compiles')
if 'global using System.IO' in (PROJ/'GlobalUsings.cs').read_text(encoding='utf-8'): ok('System.IO is globally imported')
else: fail('GlobalUsings must import System.IO')
if 'Microsoft.WindowsAppSDK' in csproj: fail('csproj still references Windows App SDK')
else: ok('csproj has no Windows App SDK')
if '<ExcludeFromSingleFile>true</ExcludeFromSingleFile>' in csproj and r'Backend\**\*' in csproj: ok('Backend Content is excluded from PublishSingleFile bundle')
else: fail('csproj must keep Backend beside the EXE via ExcludeFromSingleFile')
if '<PublishSingleFile>false</PublishSingleFile>' in csproj and '<UseWPF>true</UseWPF>' in csproj: ok('WPF self-contained folder deploy (no single-file)')
else: fail('PublishSingleFile must be false')
app_xaml=(PROJ/'App.xaml').read_text(encoding='utf-8')
if 'XamlControlsResources' in app_xaml: fail('App.xaml must not merge WinUI XamlControlsResources')
else: ok('App.xaml is WPF primitive resources')
if 'CardStrokeBrush' in app_xaml and 'MutedTextBrush' in app_xaml: ok('App.xaml defines fallback card/muted brushes')
else: fail('App.xaml missing CardStrokeBrush/MutedTextBrush')
if not (PROJ/'MainWindow.xaml').exists(): fail('MainWindow.xaml missing')
else: ok('MainWindow is WPF XAML')
if 'NavigationView' in (PROJ/'MainWindow.xaml').read_text(encoding='utf-8'): fail('MainWindow must not use NavigationView')
else: ok('MainWindow does not use NavigationView')
if (PROJ/'Controls'/'StatusBanner.cs').exists(): ok('StatusBanner replaces InfoBar')
else: fail('StatusBanner missing')
program=(PROJ/'Program.cs').read_text(encoding='utf-8')
if 'new App();' in program and 'app.Run()' in program: ok('WPF custom Main calls App.Run')
else: fail('Program.Main must create WPF App and Run')
startup=(PROJ/'StartupGuard.cs').read_text(encoding='utf-8')
if 'wpfgfx_cor3.dll' in startup and 'PresentationNative_cor3.dll' in startup and 'Microsoft.ui.xaml.dll' not in startup: ok('startup probes WPF native runtime')
else: fail('startup still probes WinUI native runtime')
if 'MICROSOFT_WINDOWSAPPRUNTIME' not in startup: ok('WASDK bootstrap directory env removed')
else: fail('WASDK environment variable leftover')
if (PROJ/'Program.cs').exists() and (PROJ/'StartupGuard.cs').exists(): ok('custom Main + startup crash log exist')
else: fail('startup guard files missing')
if bj.get('WindowsAppSDK')=='WPF' and bj.get('DotNet')=='10.0' and bj.get('Language')=='C# 14' and bj.get('Version')=='4.3.0': ok('BuildInfo technology metadata')
else: fail('BuildInfo technology metadata mismatch')

if 'Microsoft YaHei UI' in app_xaml: ok('Chinese UI font stack')
else: fail('App.xaml missing Microsoft YaHei UI font stack')
if app_xaml.find('Microsoft YaHei UI') < app_xaml.find('Segoe UI'): ok('YaHei is preferred over Segoe for CJK')
else: fail('Segoe UI is still preferred over YaHei and will clip Chinese captions')
coord=(PROJ/'Services'/'RepairWorkflowCoordinator.cs').read_text(encoding='utf-8')
if 'return TransitionAsync(phase, type, group, eligible, planState, detail, cancellationToken, allowRestart: true);' in coord: ok('RecordPlan allows restart from terminal phases')
else: fail('RecordPlan must allowRestart so RepairCompleted can start a new Dry Run')
active=coord.split('IsActiveRepairPhase',1)[1].split('CanTransition',1)[0]
if 'RepairCompleted' in active: fail('RepairCompleted must not block a new diagnosis cycle')
else: ok('RepairCompleted is not an active repair phase')
if 'RepairWorkflowPhase.RepairCompleted => to is RepairWorkflowPhase.VerificationRunning or RepairWorkflowPhase.Observing or RepairWorkflowPhase.Verified or RepairWorkflowPhase.Diagnosed or RepairWorkflowPhase.Planned or RepairWorkflowPhase.Eligible' in coord: ok('RepairCompleted can start a new plan cycle')
else: fail('RepairCompleted cannot transition to Planned')
jsonh=(PROJ/'Services'/'JsonHelpers.cs').read_text(encoding='utf-8')
if 'OrdinalIgnoreCase' in jsonh and 'JsonValueKind.String' in jsonh: ok('JSON bool accepts PowerShell strings')
else: fail('JsonHelpers.Bool too strict for PowerShell JSON')
sess=(PROJ/'Services'/'SessionLogService.cs').read_text(encoding='utf-8')
appservices=(PROJ/'AppServices.cs').read_text(encoding='utf-8')
if 'session-' in sess and 'Flush()' in sess and 'BUG' in sess: ok('session usage log service')
else: fail('session log missing')
if 'SessionLog.Flush' in appservices: ok('session log flushed on close')
else: fail('session log not flushed on dispose')
engine_text=(BACK/'RepairCenter.ps1').read_text(encoding='utf-8')
if "$host='" in engine_text or 'try{$host=' in engine_text: fail('RepairCenter must not assign to PowerShell automatic $Host')
else: ok('RepairCenter does not clobber $Host')
if '$finalHost' in engine_text: ok('Microsoft trust result uses $finalHost')
else: fail('Microsoft trust result still uses $host')
if '已停用 Microsoft 官方安装器对比' in engine_text: ok('local-healthy VC++ is PASS without Microsoft installer compare')
else: fail('VC++ diagnostic still depends on Microsoft official installer compare')
if '点击一键诊断/运行库联网检测后会与 Microsoft 官方最新版本比较' in engine_text: fail('VC++ still WARNs waiting for online compare')
else: ok('VC++ no longer asks the user to online-compare for health')
if "Status -in @('N/A','INFO')" in engine_text or 'Status -in @(\'N/A\',\'INFO\')' in engine_text or "$r.Status -in @('N/A','INFO')" in engine_text: ok('final verification treats INFO as PASS')
else: fail('final verification still maps INFO to WARN')
if '$eligible=$false' in engine_text.replace(' ', '') or '$eligible = $false' in engine_text: ok('runtime auto-repair via official installer is disabled')
else: fail('runtime repair eligibility still allows official-installer repair')
online_fn=engine_text.split('function Update-RuntimeOnlineInfo',1)[1].split('function Get-OfficialVC14Target',1)[0]
if 'Get-VCRedistOnlinePackage' in online_fn or 'Get-DirectXWebInstaller' in online_fn or 'Invoke-OfficialMicrosoftDownload' in online_fn: fail('Update-RuntimeOnlineInfo still downloads Microsoft installers')
else: ok('Update-RuntimeOnlineInfo is a retired no-download stub')
if 'function Get-OfficialVC14Target' in engine_text and '14.42.0.0' in engine_text: ok('VC++ keeps offline official-baseline comparison')
else: fail('VC++ offline version comparison missing')
diag_fn=engine_text.split('function Get-RuntimeDiagnosticRows',1)[1].split('function Write-RuntimeOnlineWorker',1)[0]
if 'RuntimeOnlineInfo' in diag_fn or '建议执行修复安装' in diag_fn: fail('runtime diagnostics still compare official packages or WARN on SideBySide')
else: ok('runtime diagnostics are local-only and do not WARN for official compare')
if 'C++ 运行库' in diag_fn and '游戏 DirectX' in diag_fn and '老游戏兼容组件' in diag_fn: ok('runtime diagnostics use customer-facing names')
else: fail('runtime diagnostic names are still jargon')
plan_fn=engine_text.split('function Format-RepairPlan',1)[1].split('function Save-Transaction',1)[0]
if '结论：' in plan_fn and 'Microsoft 官方包信任证据' not in plan_fn and 'SHA256=' not in plan_fn: ok('repair plan text leads with a customer conclusion')
else: fail('repair plan text still dumps hashes/paths')
verify_fn=engine_text.split('function Run-FinalVerification',1)[1].split('function Test-BrokerIntegrity',1)[0]
if 'installed=' in verify_fn or 'runtime=' in verify_fn: fail('final verification still prints installed=/runtime= jargon')
else: ok('final verification prints customer results')
headless_fn=engine_text.split('function Invoke-RuntimeRepairHeadless',1)[1].split('function Invoke-ContinuePendingRepairHeadless',1)[0]
if 'Update-RuntimeOnlineInfo' in headless_fn or 'Invoke-RuntimeAutoRepair' in headless_fn: fail('runtime repair headless still tries Microsoft installer repair')
else: ok('runtime repair headless refuses without downloading')
bridge_text=(BACK/'UiBridge.ps1').read_text(encoding='utf-8')
if "[void](Update-RuntimeOnlineInfo" in bridge_text: fail('UiBridge still runs Microsoft online compare')
else: ok('UiBridge RUNTIME_ONLINE/PLAN_RUNTIME no longer download Microsoft installers')
if 'ApplicationIcon' in csproj and r'Assets\app.ico' in csproj: ok('application icon is embedded')
else: fail('csproj missing ApplicationIcon')
if not (PROJ/'Assets'/'app.ico').exists(): fail('app.ico missing')
else: ok('app.ico present')
launcher_cs=(ROOT/'Launcher'/'SelfHealingCenter.cs').read_text(encoding='utf-8') if (ROOT/'Launcher'/'SelfHealingCenter.cs').exists() else ''
if 'InnerExeName' in launcher_cs and 'WorkingDirectory' in launcher_cs and 'App' in launcher_cs: ok('desktop launcher starts App inner EXE')
else: fail('desktop launcher source missing or incomplete')
readme=(ROOT/'README.txt').read_text(encoding='utf-8') if (ROOT/'README.txt').exists() else ''
if '双击' in readme and '开始菜单' in readme: ok('end-user readme explains double-click launch')
else: fail('使用说明.txt missing double-click launch instructions')
if '从开始菜单打开' in startup: fail('startup still tells the user to launch from the Start Menu')
else: ok('startup does not instruct Start Menu launch')
runtime_xaml=(PROJ/'Pages'/'RuntimePage.xaml').read_text(encoding='utf-8')
safety_xaml=(PROJ/'Pages'/'SafetyPage.xaml').read_text(encoding='utf-8')
if '<ScrollViewer>' in runtime_xaml and 'ItemsControl' in runtime_xaml: ok('runtime page uses page-level wheel scroll')
else: fail('runtime page still traps wheel inside nested ListView')
if '联网对比' in runtime_xaml or '安全修复' in runtime_xaml or '官方包信任证据' in runtime_xaml: fail('runtime Microsoft compare/repair UI must be removed')
else: ok('runtime page is local-only detection')
if 'DisplayName' in runtime_xaml and 'DisplayStatus' in runtime_xaml and 'ResultLine' in runtime_xaml: ok('runtime cards show customer-facing result labels')
else: fail('runtime cards still bind raw Name/Status/Detail jargon')
if '奥创更新错误' in safety_xaml: ok('ASUS page is update-error focused')
else: fail('ASUS page still looks like generic system health')
if 'TopNavButton' in app_xaml and '奥创修复中心' in (PROJ/'MainWindow.xaml').read_text(encoding='utf-8'): ok('single top chrome without duplicate title')
else: fail('main window still duplicates the long product title')
if '自愈中心' in (PROJ/'MainWindow.xaml').read_text(encoding='utf-8'): fail('main window still uses old product name 自愈中心')
else: ok('product renamed to 奥创修复中心')
maint=(PROJ/'Services'/'SystemMaintenanceService.cs').read_text(encoding='utf-8')
settings_xaml=(PROJ/'Pages'/'SettingsPage.xaml').read_text(encoding='utf-8')
for token,msg in [
    ('EmptyWorkingSet','memory cleaner uses EmptyWorkingSet'),
    ('SHEmptyRecycleBin','cache cleaner can empty recycle bin'),
    ('shader','cache cleaner excludes shader caches'),
]:
    ok(msg) if token in maint else fail('maintenance missing '+token)
if '系统缓存清理' in settings_xaml and '内存清理' in settings_xaml and '本软件检测缓存' in settings_xaml: ok('settings page is system tools not conflicting advanced diagnostics')
else: fail('settings page missing cache/memory tools')
if '高级设置' in (PROJ/'Pages'/'ReportsPage.xaml').read_text(encoding='utf-8'): fail('reports still labels the tools page 高级设置')
else: ok('reports opens 系统工具')

# No-feature-reduction capability baseline. This is shipped and hash-locked by BuildInfo.
cap_path=BACK/'CapabilityBaseline.json'
cap=json.loads(cap_path.read_text(encoding='utf-8'))
if sha(cap_path)==bj.get('CapabilityBaselineSHA256',''): ok('capability baseline hash-lock')
else: fail('capability baseline hash mismatch')
if cap.get('Policy')=='NO_FEATURE_REDUCTION' and cap.get('AsusCore',{}).get('Priority')=='CORE': ok('ASUS capability baseline marked core/non-reducible')
else: fail('ASUS capability baseline policy missing')
bridge=(BACK/'UiBridge.ps1').read_text(encoding='utf-8')
broker=(BACK/'ElevatedBroker.ps1').read_text(encoding='utf-8')
engine=(BACK/'RepairCenter.ps1').read_text(encoding='utf-8')
recipe=(BACK/'RecipeCatalog.psd1').read_text(encoding='utf-8')
for action in cap['AsusCore']['BridgeActions']+cap['Runtime']['BridgeActions']+cap['CrashDump']['BridgeActions']:
    token = action
    if action.startswith('BROKER_PREPARE_'): token='BROKER_PREPARE_*'
    if token in bridge: ok('bridge capability '+action)
    else: fail('bridge capability missing '+action)
for action in cap['AsusCore']['BrokerActions']+cap['Runtime']['BrokerActions']+cap['CrashDump']['BrokerActions']:
    if action in broker: ok('broker capability '+action)
    else: fail('broker capability missing '+action)
for fn in cap['AsusCore']['EngineFunctions']+cap['Runtime']['EngineFunctions']+cap['CrashDump']['EngineFunctions']:
    if re.search(r'^function\s+'+re.escape(fn)+r'\b',engine,re.M): ok('engine capability '+fn)
    else: fail('engine capability missing '+fn)
for group,recipe_id in cap['AsusCore']['Recipes'].items():
    if recipe_id in recipe: ok('ASUS recipe '+group)
    else: fail('ASUS recipe missing '+group)
for group,expected in cap['AsusCore']['LegacyHashes'].items():
    ent=lock['Modules'][group]
    if expected.lower()==ent['SHA256'].lower()==sha(ROOT/ent['File']): ok('ASUS immutable baseline '+group)
    else: fail('ASUS immutable baseline mismatch '+group)
reports_page=(PROJ/'Pages'/'ReportsPage.xaml').read_text(encoding='utf-8')
for token in ['TransactionId','重启后续跑']:
    ok('report/history capability '+token) if token in reports_page else fail('report/history capability missing '+token)
for page in cap['ReportsAdvanced']['Pages']:
    if (PROJ/'Pages'/(page+'.xaml')).exists() and (PROJ/'Pages'/(page+'.xaml.cs')).exists(): ok('advanced page retained '+page)
    else: fail('advanced page missing '+page)

# User-accessible parity with the v3.1 stable UI operations after navigation consolidation.
ui_contracts={
    'Pages/SafetyPage.xaml.cs':['RunAsync("PLAN_ASUS"','ASUS_REPAIR'],
    'Pages/RuntimePage.xaml.cs':['ReadComponentStatesAsync("RUNTIME"','RunAsync("DASHBOARD"'],
    'Pages/CrashPage.xaml.cs':['AnalyzeDump_Click','WER_ENABLE','WER_DISABLE','RunGpuDiagnosisAsync','GPU_SAFE_REPAIR'],
    'Pages/ReportsPage.xaml.cs':['RunAsync("TRANSACTIONS"','RunAsync("VERIFY"','RunAsync("EXPORT_REPORT"','CONTINUE','GenerateSystemHealthReportAsync','GenerateRepairReportAsync'],
    'Pages/SettingsPage.xaml.cs':['DeepTestPage','IdentityPage','ArchitecturePage'],
}
for rel,tokens in ui_contracts.items():
    raw=(PROJ/rel).read_text(encoding='utf-8')
    for token in tokens:
        if token in raw: ok('UI capability '+rel+': '+token)
        else: fail('UI capability missing '+rel+': '+token)

# one-click version + Windows cmd launcher encoding regression guard
one=(ROOT/'OneClick-Win11.ps1').read_text(encoding='utf-8')

# Windows PowerShell 5.1 gate compatibility: JSON must be read explicitly as UTF-8 and fatal errors must surface.
arch_test=(ROOT/'Tests'/'Architecture.Tests.ps1').read_text(encoding='utf-8-sig')
if all(x in arch_test for x in ['function Read-Utf8Json','System.Text.UTF8Encoding','[IO.File]::ReadAllText','[FATAL] Architecture.Tests.ps1 line','ParseInput']): ok('PS5.1 static gate uses explicit UTF-8 JSON + fatal diagnostics')
else: fail('PS5.1 static gate UTF-8/fatal diagnostics missing')
if all(x in arch_test for x in ["$buildJson=Read-Utf8Json", "$lock=Read-Utf8Json", "try{$capability=Read-Utf8Json"]): ok('all static-gate JSON inputs bypass Windows PowerShell default code page')
else: fail('static-gate JSON still depends on Windows PowerShell default code page')
if all(x in one for x in ['StaticTests_','2>&1','Set-Content -LiteralPath $StaticLog -Encoding UTF8','详细日志']): ok('OneClick preserves child static-test stdout/stderr in dedicated log')
else: fail('OneClick child static-test diagnostic capture missing')
if all(x in one for x in ['https://dot.net/v1/dotnet-install.ps1','Install-DotNet10SdkLocal',"'-Channel','10.0'","'-Quality','GA'",'source update --name winget','0x8A15000F']): ok('OneClick robust .NET 10 SDK bootstrap fallback')
else: fail('OneClick robust .NET SDK bootstrap fallback missing')
if 'source reset' not in one: ok('OneClick does not auto-reset WinGet sources')
else: fail('OneClick auto-reset of WinGet sources is forbidden')
if 'publish 目录缺少 Backend' in one and '孤立 EXE' in one and '$DesktopExe' not in one: ok('OneClick never ships a bare EXE without hash-locked Backend')
else: fail('OneClick bare-EXE delivery regression')
if 'Materialize hash-locked Backend' in one and r'WindowsGameRuntimeASUSSelfHealing.WinUI\Backend' in one: ok('OneClick materializes hash-locked Backend beside published EXE')
else: fail('OneClick no longer copies Backend beside published EXE')
if "-p:PublishSingleFile=false" in one and 'wpfgfx_cor3.dll' in one: ok('OneClick forbids WPF PublishSingleFile payload')
else: fail('OneClick still publishes as a single file')
if re.search(r"(?m)^\s*\$Version\s*=\s*'"+re.escape(bj['Version'])+r"'\s*$",one): ok('OneClick '+bj['Version'])
else: fail('OneClick version mismatch')
for launcher_name in ['一键构建并启动_Win11.cmd','Launch-Win11.cmd','Build-WinUI3.cmd']:
    raw=(ROOT/launcher_name).read_bytes()
    if raw.startswith(b'\xef\xbb\xbf'): fail('launcher UTF-8 BOM forbidden '+launcher_name)
    else: ok('launcher BOM-free '+launcher_name)
    if all(x < 128 for x in raw): ok('launcher ASCII-only '+launcher_name)
    else: fail('launcher contains non-ASCII bytes '+launcher_name)
    bad_lf=any(raw[i]==10 and (i==0 or raw[i-1]!=13) for i in range(len(raw)))
    if not bad_lf and b'\r\n' in raw: ok('launcher CRLF '+launcher_name)
    else: fail('launcher line endings are not strict CRLF '+launcher_name)
    txt=raw.decode('ascii',errors='replace')
    expected_script='Build-WinUI3.ps1' if launcher_name == 'Build-WinUI3.cmd' else 'OneClick-Win11.ps1'
    if txt.startswith('@echo off\r\n') and 'chcp 65001' not in txt.lower() and expected_script in txt:
        ok('launcher command contract '+launcher_name)
    else:
        fail('launcher command contract drift '+launcher_name)

report=ROOT/f"STATIC_VALIDATION_v{bj['Version']}.txt"
lines=[f"Windows Game Runtime / ASUS Armoury Self-Healing Center v{bj['Version']}",f'Local source-invariant validation: {len(passes)} PASS / {len(failures)} FAIL','']
lines += ['PASS: '+x for x in passes]
if failures: lines += ['']+['FAIL: '+x for x in failures]
report.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(lines[0]); print(lines[1])
for x in failures: print('FAIL',x)
sys.exit(1 if failures else 0)
