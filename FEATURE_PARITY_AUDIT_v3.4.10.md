# Feature Parity Audit v3.4.10

v3.4.10 is a launch-blocker packaging hotfix. Core engines are unchanged.

Retained without reduction:
- ASUS 4151/4152 eligibility -> plan -> broker -> repair -> reboot continuation -> verification -> observation;
- immutable PV/HOLTEK/ENE hash-lock;
- VC++ / DirectX diagnosis and repair;
- incremental crash/WER/PnP event diagnostics;
- local Dump/LiveKernel analysis;
- ReBAR + Dedicated/Shared GPU memory + TDR + vendor driver + WHEA + power temporal correlation;
- EVIDENCE_INSUFFICIENT as the weak-evidence GPU class;
- rollback-oriented GPU safe repair only for software-side DRIVER_TDR classification;
- SQLite state/incident/transaction/workflow cache outside the Setup uninstall path;
- reports, transaction history, final verification, and advanced diagnostic pages.

RepairCenter.ps1 and PV/HOLTEK/ENE hashes are unchanged from v3.4.8 / v3.4.9.
The only user-visible product change is that the installed GUI actually opens.
