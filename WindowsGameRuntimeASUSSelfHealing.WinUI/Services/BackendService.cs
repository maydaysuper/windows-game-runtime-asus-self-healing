using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services.Contracts;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class BackendService : IBackendClient, IDisposable
{
    // RepairCenter.ps1 expands hash-locked legacy modules during import. Keep all engine-backed
    // actions serialized so two PowerShell processes never race on those shared module files.
    // Read-only crash telemetry uses a separate bridge and can run concurrently with the engine.
    private readonly SemaphoreSlim _engineGate = new(1, 1);
    private readonly SemaphoreSlim _telemetryGate = new(1, 1);
    private readonly string _backendRoot;
    private readonly string _bridgePath;
    private readonly string _enginePath;
    private readonly string _brokerPath;
    private readonly string _eventReaderPath;
    private readonly string _gpuDiagnosticsReaderPath;
    private readonly string _gpuSafeRepairPath;
    private readonly string _buildInfoJsonPath;
    private readonly string _buildInfoPsd1Path;
    private readonly string _capabilityBaselinePath;
    private readonly AdaptiveResourceGovernor _resources;

    public string BackendRoot => _backendRoot;
    public string EnginePath => _enginePath;
    public string BrokerPath => _brokerPath;

    public BackendService(AdaptiveResourceGovernor resources)
    {
        _resources = resources;
        _backendRoot = Path.Combine(AppContext.BaseDirectory, "Backend");
        _bridgePath = Path.Combine(_backendRoot, "UiBridge.ps1");
        _enginePath = Path.Combine(_backendRoot, "RepairCenter.ps1");
        _brokerPath = Path.Combine(_backendRoot, "ElevatedBroker.ps1");
        _eventReaderPath = Path.Combine(_backendRoot, "IncrementalEventReader.ps1");
        _gpuDiagnosticsReaderPath = Path.Combine(_backendRoot, "GpuDiagnosticsReader.ps1");
        _gpuSafeRepairPath = Path.Combine(_backendRoot, "GpuSafeRepair.ps1");
        _buildInfoJsonPath = Path.Combine(_backendRoot, "BuildInfo.json");
        _buildInfoPsd1Path = Path.Combine(_backendRoot, "BuildInfo.psd1");
        _capabilityBaselinePath = Path.Combine(_backendRoot, "CapabilityBaseline.json");
    }

    public BuildIdentity GetBuildIdentity()
    {
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(_buildInfoJsonPath, Encoding.UTF8));
            var root = doc.RootElement;
            return new BuildIdentity(
                root.GetProperty("Version").GetString() ?? "3.4.9",
                root.GetProperty("BuildId").GetString() ?? "unknown",
                root.TryGetProperty("WindowsAppSDK", out var was) ? was.GetString() ?? "" : "",
                root.TryGetProperty("DotNet", out var dotnet) ? dotnet.GetString() ?? "" : "",
                root.TryGetProperty("Language", out var language) ? language.GetString() ?? "" : "",
                root.GetProperty("EngineSHA256").GetString() ?? "",
                root.GetProperty("BrokerSHA256").GetString() ?? "",
                root.GetProperty("UiBridgeSHA256").GetString() ?? "",
                root.GetProperty("EventReaderSHA256").GetString() ?? "",
                root.TryGetProperty("GpuDiagnosticsReaderSHA256", out var gpuReader) ? gpuReader.GetString() ?? "" : "",
                root.TryGetProperty("GpuSafeRepairSHA256", out var gpuRepair) ? gpuRepair.GetString() ?? "" : "",
                root.GetProperty("AtomicPolicyExecutorSHA256").GetString() ?? "",
                root.GetProperty("RecipeCatalogSHA256").GetString() ?? "",
                root.GetProperty("BuildInfoSHA256").GetString() ?? "",
                root.TryGetProperty("CapabilityBaselineSHA256", out var baseline) ? baseline.GetString() ?? "" : "");
        }
        catch
        {
            return new BuildIdentity("3.4.9", "unknown", "", "", "", "", "", "", "", "", "", "", "", "", "");
        }
    }

    public async Task<BridgeResult> RunAsync(
        string action,
        string? group = null,
        string? exeName = null,
        bool force = false,
        string? sinceUtc = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var telemetryOnly = action.Equals("CRASH_DELTA", StringComparison.OrdinalIgnoreCase) || action.Equals("GPU_DIAGNOSTICS", StringComparison.OrdinalIgnoreCase);
        var gate = telemetryOnly ? _telemetryGate : _engineGate;
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        IDisposable? resourceLease = null;
        var resultPath = Path.Combine(Path.GetTempPath(), $"WGRASH_{SanitizeAction(action)}_{Guid.NewGuid():N}.json");
        try
        {
            resourceLease = await _resources.EnterBackgroundWorkAsync(cancellationToken).ConfigureAwait(false);
            EnsureBackendPresent(telemetryOnly ? BackendTrustScope.Telemetry : BackendTrustScope.Engine);
            var psi = new ProcessStartInfo
            {
                FileName = PowerShellExe(),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };
            AddArg(psi, "-NoProfile");
            AddArg(psi, "-NonInteractive");
            AddArg(psi, "-ExecutionPolicy"); AddArg(psi, "Bypass");
            AddArg(psi, "-WindowStyle"); AddArg(psi, "Hidden");
            AddArg(psi, "-File"); AddArg(psi, _bridgePath);
            AddArg(psi, "-Action"); AddArg(psi, action);
            AddArg(psi, "-ResultPath"); AddArg(psi, resultPath);
            AddArg(psi, "-EnginePath"); AddArg(psi, _enginePath);
            if (!string.IsNullOrWhiteSpace(group)) { AddArg(psi, "-Group"); AddArg(psi, group); }
            if (!string.IsNullOrWhiteSpace(exeName)) { AddArg(psi, "-ExeName"); AddArg(psi, exeName); }
            if (!string.IsNullOrWhiteSpace(sinceUtc)) { AddArg(psi, "-SinceUtc"); AddArg(psi, sinceUtc); }
            if (force) AddArg(psi, "-Force");

            using var process = Process.Start(psi) ?? throw new InvalidOperationException("无法启动 PowerShell backend worker。");
            _resources.TuneChildProcess(process, telemetryOnly);
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(timeout ?? TimeSpan.FromMinutes(3));
            try
            {
                await process.WaitForExitAsync(timeoutCts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                TryKill(process);
                throw new TimeoutException($"后台任务 {action} 超时。任务已终止，WinUI 主线程未被阻塞。");
            }
            catch (OperationCanceledException)
            {
                // RunAsync only hosts read-only/plan/preparation workers. Destructive repair work is
                // isolated in ElevatedBroker and is intentionally never killed by this cancellation path.
                TryKill(process);
                throw;
            }

            cancellationToken.ThrowIfCancellationRequested();
            var stderr = await stderrTask.ConfigureAwait(false);
            _ = await stdoutTask.ConfigureAwait(false);
            if (!File.Exists(resultPath))
            {
                var detail = string.IsNullOrWhiteSpace(stderr) ? "无 stderr" : stderr.Trim();
                return new BridgeResult
                {
                    Success = false,
                    Action = action,
                    Error = $"后台任务未生成结果文件，ExitCode={process.ExitCode}; {detail}"
                };
            }

            var json = await File.ReadAllTextAsync(resultPath, Encoding.UTF8, cancellationToken).ConfigureAwait(false);
            var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            var success = root.TryGetProperty("Success", out var successEl) && successEl.GetBoolean();
            var error = root.TryGetProperty("Error", out var errorEl) ? errorEl.GetString() ?? "" : "";
            if (!success && string.IsNullOrWhiteSpace(error) && !string.IsNullOrWhiteSpace(stderr)) error = stderr.Trim();
            return new BridgeResult { Success = success, Action = action, Error = error, Document = document };
        }
        finally
        {
            try { if (File.Exists(resultPath)) File.Delete(resultPath); } catch { }
            resourceLease?.Dispose();
            gate.Release();
        }
    }

    public void EnsureBackendPresent() => EnsureBackendPresent(BackendTrustScope.Engine);

    private void EnsureBackendPresent(BackendTrustScope scope)
    {
        var required = scope == BackendTrustScope.Telemetry
            ? new[] { _bridgePath, _eventReaderPath, _gpuDiagnosticsReaderPath, _buildInfoJsonPath, _buildInfoPsd1Path, _capabilityBaselinePath }
            : new[] { _bridgePath, _enginePath, _brokerPath, _eventReaderPath, _gpuDiagnosticsReaderPath, _gpuSafeRepairPath, _buildInfoJsonPath, _buildInfoPsd1Path, _capabilityBaselinePath,
                Path.Combine(_backendRoot, "AtomicPolicyExecutor.ps1"), Path.Combine(_backendRoot, "RecipeCatalog.psd1") };

        foreach (var path in required)
            if (!File.Exists(path)) throw new FileNotFoundException("WinUI 后端文件缺失。", path);

        var id = GetBuildIdentity();
        ValidateHash(_bridgePath, id.UiBridgeSha256, "UiBridge");
        ValidateHash(_buildInfoPsd1Path, id.BuildInfoSha256, "BuildInfo.psd1");
        ValidateHash(_capabilityBaselinePath, id.CapabilityBaselineSha256, "CapabilityBaseline");
        if (scope == BackendTrustScope.Telemetry)
        {
            ValidateHash(_eventReaderPath, id.EventReaderSha256, "IncrementalEventReader");
            ValidateHash(_gpuDiagnosticsReaderPath, id.GpuDiagnosticsReaderSha256, "GpuDiagnosticsReader");
            return;
        }

        ValidateHash(_enginePath, id.EngineSha256, "Engine");
        ValidateHash(_brokerPath, id.BrokerSha256, "Broker");
        ValidateHash(_eventReaderPath, id.EventReaderSha256, "IncrementalEventReader");
        ValidateHash(_gpuDiagnosticsReaderPath, id.GpuDiagnosticsReaderSha256, "GpuDiagnosticsReader");
        ValidateHash(_gpuSafeRepairPath, id.GpuSafeRepairSha256, "GpuSafeRepair");
        ValidateHash(Path.Combine(_backendRoot, "AtomicPolicyExecutor.ps1"), id.AtomicPolicyExecutorSha256, "AtomicPolicyExecutor");
        ValidateHash(Path.Combine(_backendRoot, "RecipeCatalog.psd1"), id.RecipeCatalogSha256, "RecipeCatalog");
    }

    private static void ValidateHash(string path, string expected, string label)
    {
        if (string.IsNullOrWhiteSpace(expected)) throw new InvalidDataException($"{label} 缺少固定 SHA256。");
        using var stream = File.OpenRead(path);
        var actual = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException($"{label} SHA256 不匹配，拒绝执行后台脚本。 expected={expected} actual={actual}");
    }

    private static void AddArg(ProcessStartInfo info, string value) => info.ArgumentList.Add(value);

    private static string PowerShellExe()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

    private static string SanitizeAction(string action)
        => new(action.Where(c => char.IsLetterOrDigit(c) || c is '_' or '-').Take(48).ToArray());

    private static void TryKill(Process process)
    {
        try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
    }

    public void Dispose()
    {
        _engineGate.Dispose();
        _telemetryGate.Dispose();
    }

    private enum BackendTrustScope
    {
        Engine,
        Telemetry
    }
}
