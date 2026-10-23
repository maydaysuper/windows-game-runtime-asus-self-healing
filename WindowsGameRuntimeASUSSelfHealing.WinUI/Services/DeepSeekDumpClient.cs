using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class DeepSeekDumpClient
{
    public const string Endpoint = "https://api.deepseek.com/chat/completions";
    public const string ModelName = "deepseek-chat";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(25) };

    public string SettingsFile { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "WindowsGameRuntimeASUSSelfHealing",
        "deepseek.json");

    public string LoadKey()
    {
        try
        {
            if (!File.Exists(SettingsFile)) return "";
            using var doc = JsonDocument.Parse(File.ReadAllText(SettingsFile));
            return doc.RootElement.TryGetProperty("ApiKey", out var key) ? (key.GetString() ?? "").Trim() : "";
        }
        catch { return ""; }
    }

    public void SaveKey(string key)
    {
        key = (key ?? "").Trim();
        if (key.Length < 8 || key.Length > 200 || key.Any(char.IsWhiteSpace))
            throw new InvalidOperationException("密钥格式不对。从 DeepSeek 开放平台复制整段密钥，不要带空格。");
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsFile)!);
        File.WriteAllText(SettingsFile, JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["ApiKey"] = key,
            ["Model"] = ModelName
        }));
    }

    public void ClearKey()
    {
        try { if (File.Exists(SettingsFile)) File.Delete(SettingsFile); }
        catch { }
    }

    public async Task<string> ExplainAsync(DumpAnalysisResult result, CancellationToken cancellationToken = default)
    {
        var key = LoadKey();
        if (string.IsNullOrEmpty(key))
            throw new InvalidOperationException("还没有保存 DeepSeek 密钥。");

        var payload = JsonSerializer.Serialize(new
        {
            model = ModelName,
            temperature = 0.2,
            max_tokens = 500,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = "你是 Windows 游戏崩溃分析助手。只根据给出的结构化摘要判断。不要索要内存页、密钥、完整 dump 或文件路径。不要建议 DDU、改 BIOS、卸载显卡驱动。用简体中文，180 字以内：最可能方向、本机下一步、仍不能确定的部分。"
                },
                new { role = "user", content = BuildUserPrompt(result) }
            }
        });
        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");
        using var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            var brief = body.Length > 160 ? body[..160] : body;
            throw new InvalidOperationException($"DeepSeek HTTP {(int)response.StatusCode}。{brief.Replace(key, "***", StringComparison.Ordinal)}");
        }
        using var doc = JsonDocument.Parse(body);
        var text = (doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? "").Trim();
        if (text.Length == 0) throw new InvalidOperationException("DeepSeek 返回是空的。");
        return text.Length > 1200 ? text[..1200] : text;
    }

    internal static string BuildUserPrompt(DumpAnalysisResult result)
    {
        var text = new StringBuilder();
        text.Append("文件名=").Append(OneLine(result.FileName, 120));
        text.Append("\n大小=").Append(result.FileSizeText);
        text.Append("\n校验=").Append(OneLine(result.VerifyStatus, 16)).Append(' ').Append(OneLine(result.VerifyDetail, 400));
        text.Append("\n异常=").Append(OneLine(result.ExceptionCode, 16)).Append(' ').Append(OneLine(result.ExceptionName, 80));
        text.Append("\n地址=").Append(OneLine(result.ExceptionAddress, 32));
        text.Append("\n模块=").Append(OneLine(result.FaultingModule, 120));
        text.Append("\n分类=").Append(OneLine(result.Category, 40)).Append(" 置信度=").Append(OneLine(result.Confidence, 16));
        text.Append("\n本机结论=").Append(OneLine(result.CoreReason, 500));
        text.Append("\n证据=").Append(OneLine(result.Evidence, 700));
        text.Append("\n不要假设未给出的内存内容。");
        return text.ToString();
    }

    private static string OneLine(string? value, int max)
    {
        var text = (value ?? "").Replace('\r', ' ').Replace('\n', ' ').Trim();
        return text.Length <= max ? text : text[..max];
    }
}
