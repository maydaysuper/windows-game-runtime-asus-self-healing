# Feature parity audit — v3.3.0

Baseline compared against: v3.1 stable + v3.2 feature additions.

## ASUS Armoury core

PASS — `RepairCenter.ps1` hash unchanged: `72a5def7d463ef0dd5ae3f0772ca4872c2759a32781661a636cdc08dc68013a8`.

PASS — Elevated Broker, Atomic Policy Executor and RecipeCatalog hashes remain unchanged from v3.1.

PASS — Legacy adapters remain immutable:
- PV: `bff8e7ded470438834f00eeb5efb4cae3312c8e6b919052a9a6161bb8a5f6a04`
- HOLTEK: `9217d88ee0632d3c36cc96e6c8edcaf5f156ab555da521511705f91dab6d2674`
- ENE: `b90eb3aba023d1fc73116b3400f7b4e66a4b2ead73799f9365096a4b3a5e9637`

PASS — PLAN_ASUS, ASUS_REPAIR, CONTINUE, VERIFY, Eligibility, Transaction, Observation and final verification remain present.

## Runtime

PASS — VC++ / DirectX online package trust, plan, repair, smoke tests and deep tests remain present and user accessible.

## Crash / Dump

PASS — incremental Event Log, GPU/PnP, WER LocalDumps, enable/disable dump policy and local Minidump analysis remain present.

## Reports / advanced diagnostics

PASS — system report, repair report, Dump report, diagnostic ZIP, Transaction ID/history, reboot continuation and final verification remain present.

PASS — DeepTestPage, IdentityPage and ArchitecturePage remain accessible from Advanced Settings.

## Regression found and fixed

The v3.2 navigation simplification left backend `VERIFY` intact but removed its last user-visible button. v3.3 restores `VERIFY` in Reports Center and adds a CI invariant so this cannot silently regress again.
