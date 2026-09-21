# v3.4.9

Build: `20260922.winui3.15`

- Inno Setup ISCC is resolved with `Select-Object -First 1` so a single match is not indexed as the character `C`.
- Open-source GitHub delivery: Windows runner publishes **Setup.exe + Portable ZIP + SHA256 + GitHub Release**. Ordinary users no longer compile.
- CI now keeps Restore/Build/Publish `.log` + `.binlog`, and on failure prints `CSxxxx` / `WMCxxxx` / `MSBxxxx` / `NETSDKxxxx` / `NUxxxx`.
- Successful `main` builds create GitHub Release `v3.4.9` with the installers attached.
- GPU classifier token `EVIDENCE_INSUFFICIENT` is now first-class (replaces `INSUFFICIENT_EVIDENCE` as the weak-evidence code). Existing 5 root-cause classes are unchanged.
- PDH / DbgHelp P/Invoke use `ExactSpelling = true` so `*W` names are not rewritten at runtime.
- Setup uninstall still does **not** delete `%LOCALAPPDATA%\WindowsGameRuntimeASUSSelfHealing\State` (Transaction / Incident / Workflow history).
- ASUS RepairCenter and PV/HOLTEK/ENE hash-lock are unchanged.
