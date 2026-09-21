# Feature parity audit v4.1.2

Frontend + one RepairCenter variable rename (`$host` → `$finalHost`) so Microsoft trust evidence can complete. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). PV / HOLTEK / ENE payloads are byte-identical.

| Surface | Status |
|---|---|
| System health / dashboard | retained; ASUS tile is 4151/4152 summary only |
| ASUS plan / eligibility / elevated repair | retained; page lists Armoury update errors instead of generic preflight |
| VC++ / DirectX online compare / dry run / repair | retained; explicit 不必修复 / 需要关注 |
| Crash / GPU / ReBAR / Dump | retained |
| Reports / verify / diagnostic ZIP | retained |
| App icon | added (shield + heal mark) |
