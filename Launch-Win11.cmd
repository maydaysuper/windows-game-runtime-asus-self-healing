@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if errorlevel 1 (
  echo [ERROR] Cannot access the extracted package folder.
  echo Please extract the ZIP completely and run this file again.
  echo.
  pause
  exit /b 10
)

set "PS=%SystemRoot%\System32\WindowsPowerShell1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

echo.
echo ================================================================
echo   Windows Game Runtime / ASUS Self-Healing Center - WinUI 3
echo   Windows 10 / 11 x64 One-Click Build and Launch
echo ================================================================
echo.
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0OneClick-Win11.ps1"
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
  echo [OK] Build workflow completed.
) else (
  echo [ERROR] Build workflow failed. ExitCode=%RC%
  echo See the newest file under BuildLogs for details.
)
echo.
pause
exit /b %RC%
