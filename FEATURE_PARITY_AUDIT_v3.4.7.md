# Feature Parity Audit v3.4.7

v3.4.7 changes only release/installer engineering and version metadata.

Retained without reduction:
- ASUS 4151/4152 eligibility -> plan -> broker -> repair -> reboot continuation -> verification -> observation;
- immutable PV/HOLTEK/ENE hash-lock;
- VC++ / DirectX diagnosis and repair;
- incremental crash/WER/PnP event diagnostics;
- local Dump/LiveKernel analysis;
- ReBAR + Dedicated/Shared GPU memory + TDR + vendor driver + WHEA + power temporal correlation;
- rollback-oriented GPU safe repair only for software-side DRIVER_TDR classification;
- SQLite state/incident/transaction/workflow cache;
- reports, transaction history, final verification, and advanced diagnostic pages.

Release hardening does not modify the core ASUS/GPU PowerShell implementation.
