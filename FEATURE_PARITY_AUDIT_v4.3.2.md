# Feature parity audit v4.3.2

Runtime detection is online compare. Mismatch starts repair. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). Hash-locked PV / HOLTEK / ENE remain byte-identical.

| Area | Status |
|---|---|
| Runtime detection | online compare vs official VC++ (winget, then cache, then official package) |
| Runtime mismatch | UPDATE + eligibility + auto-prompt repair |
| Runtime missing files | REPAIR + auto-prompt repair |
| Offline / official source down | local files only; do not pretend compared; no auto-repair |
| Newer-than-official local | PASS; no downgrade |
| Runtime auto-repair | restored; system installer preferred for version updates |
| Microsoft dashboard package cards | still retired from customer UI |
| ASUS 4151/4152 hash-lock | unchanged |
| Cache / memory tools | unchanged |
| Desktop launch, no Start Menu | unchanged |
