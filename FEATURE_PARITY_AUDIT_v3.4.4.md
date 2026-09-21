# FEATURE PARITY AUDIT v3.4.4

结论：v3.4.4 是构建链热修复，不删减产品能力。

- ASUS 4151/4152 自愈：保留
- Legacy PV/HOLTEK/ENE hash-lock：保留
- Eligibility / Recipe / Atomic Policy：保留
- Transaction / reboot continuation / Observation / VERIFY：保留
- VC++ / DirectX 检测与修复：保留
- Crash / GPU / ReBAR / VRAM / TDR / WHEA：保留
- WER / Dump 本地分析：保留
- 系统、修复、Dump、GPU 报告：保留
- SQLite 增量事件 / Incident / Component State：保留
- AdaptiveResourceGovernor：保留

新增仅为 `.NET 10 SDK` 构建依赖自愈，不改变运行时修复策略。
