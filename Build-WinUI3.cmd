@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if errorlevel 1 exit /b 10
set "PS=%SystemRoot%\System32\WindowsPowerShell1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-WinUI3.ps1"
set "RC=%ERRORLEVEL%"
pause
exit /b %RC%
