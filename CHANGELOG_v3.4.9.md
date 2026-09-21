# v3.4.9

Build: `20260922.winui3.15`

- PublishSingleFile no longer swallows Backend: `ExcludeFromSingleFile` plus CI/OneClick copy RepairCenter next to the EXE before packaging. Hash-lock files stay on disk.
- Open-source GitHub delivery: Windows runner publishes **Setup.exe + Portable ZIP + SHA256 + GitHub Release**. Ordinary users no longer compile.
- CI now keeps Restore/Build/Publish `.log` + `.binlog`, and on failure prints `CSxxxx` / `WMCxxxx` / `MSBxxxx` / `NETSDKxxxx` / `NUxxxx`.
- Successful `main` builds create GitHub Release `v3.4.9` with the installers attached.
- GPU classifier token `EVIDENCE_INSUFFICIENT` is now first-class (replaces `INSUFFICIENT_EVIDENCE` as the weak-evidence code). Existing 5 root-cause classes are unchanged.
- PDH / DbgHelp P/Invoke use `ExactSpelling = true` so `*W` names are not rewritten at runtime.
- Setup uninstall still does **not** delete `%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\State` (Transaction / Incident / Workflow history).
- ASUS RepairCenter and PV/HOLTEK/ENE hash-lock are unchanged.
