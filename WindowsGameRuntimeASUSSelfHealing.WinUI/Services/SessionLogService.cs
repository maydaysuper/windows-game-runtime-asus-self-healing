using System.Collections.Concurrent;
using System.Text;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class SessionLogService : IDisposable
{
    private readonly ConcurrentQueue<string> _lines = new();
    private readonly DateTimeOffset _started = DateTimeOffset.Now;
    private readonly string _sessionPath;
    private readonly string _latestPath;
    private int _bugs;
    private int _flushed;

    public SessionLogService()
    {
        Directory.CreateDirectory(StartupGuard.LogDirectory);
        var stamp = _started.ToString("yyyyMMdd-HHmmss");
        _sessionPath = Path.Combine(StartupGuard.LogDirectory, "session-" + stamp + ".log");
        _latestPath = Path.Combine(StartupGuard.LogDirectory, "session-latest.log");
        Note("SESSION_START", StartupGuard.RuntimeSnapshot());
    }

    public string SessionPath => _sessionPath;
    public int BugCount => Volatile.Read(ref _bugs);

    public void Note(string source, string message) => Enqueue("NOTE", source, message);

    public void Bug(string source, Exception ex)
    {
        Interlocked.Increment(ref _bugs);
        Enqueue("BUG", source, ex.GetType().FullName + ": " + ex.Message + Environment.NewLine + ex);
    }

    public void Bug(string source, string message)
    {
        Interlocked.Increment(ref _bugs);
        Enqueue("BUG", source, message);
    }

    public string Flush()
    {
        if (Interlocked.Exchange(ref _flushed, 1) == 1) return _sessionPath;
        var duration = DateTimeOffset.Now - _started;
        var body = new StringBuilder()
            .AppendLine("Windows Game Runtime / ASUS Armoury Self-Healing Center")
            .AppendLine("session-end=" + DateTimeOffset.Now.ToString("o"))
            .AppendLine("started=" + _started.ToString("o"))
            .AppendLine("duration-sec=" + ((int)duration.TotalSeconds).ToString())
            .AppendLine("bugs=" + BugCount.ToString())
            .AppendLine("log=" + _sessionPath)
            .AppendLine()
            .AppendLine("--- events ---");
        foreach (var line in _lines)
            body.AppendLine(line);
        body.AppendLine();
        body.AppendLine(BugCount == 0
            ? "本次运行未捕获到程序故障。界面上的 INFO/WARN 仅表示证据不完整或无需修复，不写入 bug。"
            : "请把本文件发给开发者。同一目录还有 session-latest.log 方便查找。");
        var text = body.ToString();
        try
        {
            File.WriteAllText(_sessionPath, text, Encoding.UTF8);
            File.WriteAllText(_latestPath, text, Encoding.UTF8);
        }
        catch { }
        return _sessionPath;
    }

    public void Dispose() => Flush();

    private void Enqueue(string level, string source, string message)
    {
        var compact = (message ?? "").Replace("\r\n", " | ").Replace('\n', ' | ');
        var line = DateTimeOffset.Now.ToString("o") + "\t" + level + "\t" + source + "\t" + compact;
        _lines.Enqueue(line);
        try { File.AppendAllText(_sessionPath, line + Environment.NewLine, Encoding.UTF8); }
        catch { }
    }
}
