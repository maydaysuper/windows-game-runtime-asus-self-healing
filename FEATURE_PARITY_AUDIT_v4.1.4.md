# Feature parity audit v4.1.4

Microsoft installer compare/repair is amputated. Local VC++ / DirectX detection remains. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). RUNTIME_ONLINE / RUNTIME_REPAIR remain as retired stubs (no download, Eligible=false).

| Surface | Status |
|---|---|
| System health / dashboard | retained |
| ASUS plan / eligibility / elevated repair | retained |
| VC++ / DirectX local detection | retained; healthy local = PASS |
| Microsoft official installer download / compare / repair | amputated; stubs refuse |
| Crash incremental Event Log | retained |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained; INFO maps to PASS |
| PV / HOLTEK / ENE hash-lock | byte-identical |
