# Feature parity audit v4.1.3

Runtime Microsoft installer compare/repair is retired by product request. Local VC++ / DirectX detection remains. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE); RUNTIME_ONLINE / RUNTIME_REPAIR remain in the engine/bridge but are no longer health gates or primary UI.

| Surface | Status |
|---|---|
| System health / dashboard | retained |
| ASUS plan / eligibility / elevated repair | retained |
| VC++ / DirectX local detection | retained; healthy local = PASS |
| Microsoft official installer download / compare / repair | removed from health + UI |
| Crash incremental Event Log | retained |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained; INFO maps to PASS |
| PV / HOLTEK / ENE hash-lock | byte-identical |
