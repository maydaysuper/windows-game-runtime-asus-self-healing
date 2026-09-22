# Feature parity audit v4.4.0

Runtime detection is file-first plus online compare. Repair re-verifies local CRT files. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). Hash-locked PV / HOLTEK / ENE remain byte-identical.

| Area | Status |
|---|---|
| Runtime detection | full CRT DLL inventory + in-process LoadLibrary of core DLLs |
| Version source | min healthy file version, registry/uninstall as fallback |
| Runtime mismatch | UPDATE + eligibility + auto-prompt repair |
| Runtime missing / mixed / unloadable | REPAIR + auto-prompt repair |
| Official compare | parallel winget, 1-minute Force coalesce, 24h disk cache fallback |
| Offline / official source down | local files + disk-cached official version; do not pretend compared if neither exists |
| Newer-than-official local | PASS; no downgrade |
| Runtime auto-repair | local installer / winget / official package; re-check files after each method |
| Microsoft dashboard package cards | still retired from customer UI |
| ASUS 4151/4152 hash-lock | unchanged |
| Cache / memory tools | unchanged |
| Desktop launch, no Start Menu | unchanged |
