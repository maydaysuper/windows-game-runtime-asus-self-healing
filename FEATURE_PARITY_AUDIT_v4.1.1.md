# Feature parity audit v4.1.1

Frontend hotfix on the v4.1.0 WPF recast. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE).

| Surface | Status |
|---|---|
| System health / dashboard | retained |
| ASUS plan / eligibility / elevated repair | retained; RepairCompleted may start a new plan |
| VC++ / DirectX online compare / dry run / repair | retained; empty Microsoft package evidence is INFO |
| Crash incremental Event Log | retained |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis (DbgHelp + MMF) | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained |
| Session usage log on exit | added |
| Deep test / identity / architecture | retained, advanced settings |
| PV / HOLTEK / ENE hash-lock | byte-identical |
| RepairCenter / Broker / Recipe / GpuSafeRepair hashes | unchanged from v3.4.8 |

UI stack: WPF + .NET 10 self-contained win-x64. Windows App SDK is not referenced.
