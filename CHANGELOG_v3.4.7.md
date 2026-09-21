# v3.4.7

Build: `20260921.winui3.13`

- Hardened the formal Windows release path around **prebuilt user artifacts**, not local source compilation.
- Added `Installer/Verify-PublishPayload.ps1` to verify the published x64 PE, the complete Backend trust chain, CapabilityBaseline hash, and immutable PV/HOLTEK/ENE hashes before packaging.
- Added `Build-Release.ps1` to generate the Portable ZIP, Setup EXE, release manifest, and SHA256 lists from one verified publish payload.
- Setup remains **per-user / non-admin** under LocalAppData; only repair actions request UAC through Elevated Broker.
- Setup explicitly requires Windows 11 Build 22000+ and x64-compatible Windows.
- Installer builder prefers **Inno Setup 7 x64** and falls back to Inno Setup 6 for build compatibility.
- Windows CI now performs: source invariants -> PowerShell/hash-lock tests -> restore -> WinUI build -> publish -> published-payload verification -> installer compiler -> Portable/Setup release artifacts.
- The ASUS RepairCenter, Broker, Atomic Policy, RecipeCatalog, PV/HOLTEK/ENE adapters, GPU/ReBAR reader/safe repair, and capability baseline are byte-for-byte unchanged from v3.4.6.
