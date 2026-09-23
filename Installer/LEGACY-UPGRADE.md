# v4.6.3 legacy upgrade boundary

Setup runs its embedded `Upgrade-Legacy.ps1` before copying the payload and
verifies the installed launcher/inner WPF host before offering to launch.
It never executes a cleanup script from the existing installation.

Cleanup is limited to `{app}` and `{app}\App`: `desktop_entry.exe/.py/.pyc`,
`python*.dll`, `Qt6*.dll`, `_internal`, `PySide6`, and `shiboken6`.
No other DLLs, executable names, sibling installations, or arbitrary historical
install directories are removed. Users upgrading a custom location should select
that same directory; Inno retains the previous registered installation path.

The whole `%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing` data tree is
protected, including SQLite State, history and logs. Installing into that tree
or its ancestors is rejected. Runtime deletion preflights every candidate;
reparse points and locked files stop the upgrade instead of silently succeeding.
Close the old program and retry if files are locked. The temporary installer
folder contains `legacy-upgrade.log`; Inno's `/LOG` captures helper exit codes.

Current-user Desktop, Start Menu and User Pinned `.lnk` files are matched by
exact old targets inside the selected installation. Existing links are retargeted
to `SelfHealingCenter.exe`, retaining their names and locations. Links that point
to another installation/program are preserved even if their names match. Common
Desktop/Start Menu links are inspected only in an elevated install. No other
user profiles, taskbar registry or CloudStore records are changed. Windows may
cache a pinned icon until Explorer refreshes; this does not justify resetting
users' taskbars. Unreadable links are preserved and logged.

The installed launcher and inner executable must both have the exact release
FileVersion, BuildInfo must agree, required self-contained native dependencies
must exist, and `SelfHealingCenter.exe --version` must succeed. The launcher
returns a failure for missing/mismatched inner binaries.

`Tests/E2E/Verify-LegacyUpgrade.ps1` runs only on disposable GitHub Actions Windows
workers. It runs the real installer over synthetic PyInstaller/Qt files, checks
State/history byte hashes and unrelated files/links, exercises junction/locked
file/State-destination rejection, repeats the upgrade, and launches the installed
WPF window via its desktop link. Both E2E gates precede artifact upload/release.
