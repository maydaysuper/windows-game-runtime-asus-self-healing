# Feature parity audit v4.2.0

Packaging/launch only. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). No engine/broker/recipe edits.

| Surface | Status |
|---|---|
| System health / dashboard | retained |
| ASUS plan / eligibility / elevated repair | retained |
| VC++ / DirectX local detection | retained; healthy local = PASS |
| Microsoft official installer download / compare / repair | amputated in 4.1.4; stubs refuse |
| Crash incremental Event Log | retained |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained; INFO maps to PASS |
| PV / HOLTEK / ENE hash-lock | byte-identical |
| Start Menu shortcut | removed by product request |
| Desktop shortcut / portable launcher | added; inner WPF host stays folder-deployed |
