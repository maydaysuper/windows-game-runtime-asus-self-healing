# Source Review v3.4.5

## Trigger
The real Windows v3.4.4 run passed architecture/hash/capability gates, installed local .NET SDK 10.0.401, completed NuGet restore, and failed only during `dotnet publish`. The old transcript did not retain the underlying MSBuild error.

## Fix
- Pin `Platform=x64` and `PlatformTarget=x64` in the WinUI project.
- Pass `-p:Platform=x64` to both `dotnet restore` and `dotnet publish`.
- Keep the supported unpackaged + WindowsAppSDK self-contained + .NET single-file configuration.
- Emit `Restore_*.log/.binlog` and `Publish_*.log/.binlog` so native MSBuild failures are no longer hidden behind ExitCode=1.

## Safety parity
ASUS RepairCenter, Elevated Broker, Atomic Policy, RecipeCatalog, PV/HOLTEK/ENE immutable adapters, GPU/ReBAR diagnostics, and GPU safe repair are byte-identical to v3.4.4.
