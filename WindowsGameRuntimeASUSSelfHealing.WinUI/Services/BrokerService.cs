using System.Diagnostics;
using System.Text.Json;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class BrokerService : IDisposable
{
    private readonly BackendService _backend;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public BrokerService(BackendService backend) => _backend = backend;

    public async Task<BrokerExecutionResult> ExecuteAsync(
        string action,
        string? group = null,
        string? exeName = null,
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        string requestPath = "";
        string responsePath = "";
        try
        {
            using var prep = await _backend.RunAsync(
                "BROKER_PREPARE_" + action,
                group,
                exeName,
                force: false,
                timeout: TimeSpan.FromSeconds(30),
                cancellationToken: cancellationToken).ConfigureAwait(false);
            if (!prep.Success)
                return new BrokerExecutionResult(false, "无法生成 Broker 请求：" + prep.Error, "PREPARE_FAILED", "");

            var payload = prep.Payload;
            requestPath = payload.GetProperty("RequestPath").GetString() ?? "";
            responsePath = payload.GetProperty("ResponsePath").GetString() ?? "";
            var brokerPath = payload.GetProperty("BrokerPath").GetString() ?? _backend.BrokerPath;
            var enginePath = payload.GetProperty("EnginePath").GetString() ?? _backend.EnginePath;
            if (string.IsNullOrWhiteSpace(requestPath) || string.IsNullOrWhiteSpace(responsePath))
                return new BrokerExecutionResult(false, "Broker 请求路径无效。", "PREPARE_FAILED", "");

            var ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            var psi = new ProcessStartInfo
            {
                FileName = ps,
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{brokerPath}\" -RequestPath \"{requestPath}\" -EnginePath \"{enginePath}\"",
                Verb = "runas",
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            Process? process;
            try { process = Process.Start(psi); }
            catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
            {
                return new BrokerExecutionResult(false, "用户取消了 UAC 提权。", "UAC_CANCELLED", "");
            }
            if (process is null) return new BrokerExecutionResult(false, "Elevated Broker 未启动。", "BROKER_START_FAILED", "");

            using (process)
            {
                using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeoutCts.CancelAfter(TimeSpan.FromMinutes(20));
                try
                {
                    await process.WaitForExitAsync(timeoutCts.Token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    // Never hard-kill an elevated repair process in the middle of MSI/DISM work.
                    return new BrokerExecutionResult(
                        false,
                        "Elevated Broker 超过 20 分钟仍在运行。为避免中断 MSI/DISM/ASUS 修复，前端没有强制结束该管理员进程；可稍后在报告中心刷新修复状态。",
                        "BROKER_STILL_RUNNING",
                        "");
                }
                catch (OperationCanceledException)
                {
                    // Cancellation only stops waiting in the standard-user GUI. The elevated process is
                    // intentionally left alone because terminating it could corrupt an MSI/DISM transaction.
                    return new BrokerExecutionResult(
                        false,
                        "前端已停止等待，但管理员修复进程不会被强制结束。请稍后从报告中心刷新最终状态。",
                        "BROKER_WAIT_CANCELLED",
                        "");
                }
            }

            for (var i = 0; i < 20 && !File.Exists(responsePath); i++)
                await Task.Delay(150, cancellationToken).ConfigureAwait(false);
            if (!File.Exists(responsePath))
                return new BrokerExecutionResult(false, "Broker 已退出但没有返回响应。", "BROKER_NO_RESPONSE", "");

            var json = await File.ReadAllTextAsync(responsePath, cancellationToken).ConfigureAwait(false);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var success = root.TryGetProperty("Success", out var ok) && ok.GetBoolean();
            var detail = root.TryGetProperty("Detail", out var d) ? d.GetString() ?? "" : "";
            var state = success ? "COMPLETED" : "FAILED";
            var transactionId = "";
            if (root.TryGetProperty("Data", out var data) && data.ValueKind == JsonValueKind.Object)
            {
                state = data.TryGetProperty("State", out var s) ? s.GetString() ?? state : state;
                transactionId = data.TryGetProperty("TransactionId", out var tx) ? tx.GetString() ?? "" : "";
            }
            return new BrokerExecutionResult(success, detail, state, transactionId);
        }
        finally
        {
            TryDelete(responsePath);
            TryDelete(requestPath);
            _gate.Release();
        }
    }

    private static void TryDelete(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    public void Dispose() => _gate.Dispose();
}
