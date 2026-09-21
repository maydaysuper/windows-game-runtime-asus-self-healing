# Source review v3.4.1

## Root cause

The v3.4.0 Chinese one-click CMD launcher was encoded as UTF-8 with BOM and Unix LF line endings. On localized `cmd.exe`, the BOM can be interpreted as visible OEM/ANSI characters (for example `锘緻`) before the first command, while LF-only batch input can produce malformed command boundaries in some environments.

## Fix

- `一键构建并启动_Win11.cmd`: ASCII-only, no BOM, CRLF.
- `Launch-Win11.cmd`: same safe launcher under an ASCII filename.
- `Build-WinUI3.cmd`: ASCII-only, no BOM, CRLF.
- Removed `chcp 65001` dependency from CMD launchers.
- PowerShell entry scripts remain UTF-8 BOM so Windows PowerShell 5.1 decodes Chinese source text reliably; their line endings are normalized to CRLF.
- Added regression checks in both PowerShell and Python static suites.

## Protected core

ASUS repair engine and immutable Legacy Adapter bytes are unchanged from v3.4.0.
