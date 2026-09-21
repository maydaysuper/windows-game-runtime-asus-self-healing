# Feature parity audit v4.3.0

Rename + system tools. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE). Hash-locked RepairCenter / PV / HOLTEK / ENE remain byte-identical.

| Surface | Status |
|---|---|
| System health / dashboard | retained |
| ASUS plan / eligibility / elevated repair | retained |
| VC++ local detection + offline version compare vs 14.42 | retained |
| DirectX core / legacy local detection | retained |
| Microsoft official installer download / auto-repair | still amputated |
| Crash incremental Event Log | retained |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained |
| DeepTest / Identity / Architecture | retained under 系统工具 → 开发诊断 |
| PV / HOLTEK / ENE hash-lock | byte-identical |
| System cache cleanup | added; skips in-use files and shader caches |
| Memory cleanup | added; EmptyWorkingSet only, no process kill |
