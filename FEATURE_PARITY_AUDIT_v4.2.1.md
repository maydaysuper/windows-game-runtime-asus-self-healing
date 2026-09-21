# Feature parity audit v4.2.1

Customer-facing copy + offline VC++ baseline comparison. CapabilityBaseline.json is unchanged (`NO_FEATURE_REDUCTION`, ASUS = CORE).

| Surface | Status |
|---|---|
| System health / dashboard | retained; customer conclusion copy |
| ASUS plan / eligibility / elevated repair | retained; plan text leads with 结论 |
| VC++ local detection + offline version compare vs 14.42 | retained |
| DirectX core / legacy local detection | retained |
| Microsoft official installer download / auto-repair | still amputated; stubs refuse |
| Crash incremental Event Log | retained; simpler labels |
| GPU / ReBAR diagnosis + safe cache rollback | retained |
| Dump analysis | retained |
| Reports / verify / diagnostic ZIP / continue-after-reboot | retained; VERIFY prints 正常/需关注/需处理 |
| PV / HOLTEK / ENE hash-lock | byte-identical |
