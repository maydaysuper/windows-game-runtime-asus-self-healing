using System.Text.RegularExpressions;
using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class ComponentItem
{
    public string Key { get; init; } = "";
    public string Name { get; init; } = "";
    public string Installed { get; init; } = "";
    public string Target { get; init; } = "";
    public string Runtime { get; init; } = "";
    public string ErrorCode { get; init; } = "";
    public string Status { get; init; } = "INFO";
    public string Detail { get; init; } = "";
    public string Group { get; init; } = "";

    public string DisplayName => Key switch
    {
        "VC_x64" => "C++ 运行库（64位）",
        "VC_x86" => "C++ 运行库（32位）",
        "VC_arm64" => "C++ 运行库（ARM）",
        "DirectXCore" => "游戏 DirectX",
        "DirectXLegacy" => "老游戏兼容组件",
        "Patriot" => "内存灯效",
        "VGA" => "显卡灯效",
        "Holtek" => "主板内存灯效",
        "ENE" => "硬盘灯效",
        _ => string.IsNullOrWhiteSpace(Name) ? Key : Name,
    };

    public string DisplayStatus => StatusPalette.Display(Status);

    public string VersionLine => string.IsNullOrWhiteSpace(Runtime) ? "" : CustomerCopy.Plain(Runtime);

    public string ResultLine
    {
        get
        {
            var detail = CustomerCopy.Plain(Detail);
            if (!string.IsNullOrWhiteSpace(detail)) return detail;
            var runtime = CustomerCopy.Plain(Runtime);
            if (!string.IsNullOrWhiteSpace(runtime)) return runtime;
            return DisplayStatus == "正常" ? "本机可用" : DisplayStatus;
        }
    }

    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}

public static class CustomerCopy
{
    private static readonly Regex PathLike = new(@"([A-Za-z]:\\|\\\\)[^\s]+", RegexOptions.Compiled);
    private static readonly Regex UrlLike = new(@"https?://\S+", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex ShaLike = new(@"\b[0-9a-fA-F]{64}\b", RegexOptions.Compiled);
    private static readonly Regex HexId = new(@"\{[0-9A-Fa-f-]{36}\}", RegexOptions.Compiled);

    public static string Plain(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";
        var t = PathLike.Replace(text, "本机文件");
        t = UrlLike.Replace(t, "");
        t = ShaLike.Replace(t, "");
        t = HexId.Replace(t, "");
        t = t.Replace("NO_ACTION_REQUIRED", "不必修复", StringComparison.OrdinalIgnoreCase);
        t = t.Replace("SHA256=", "", StringComparison.OrdinalIgnoreCase);
        t = Regex.Replace(t, @"\s+", " ").Trim();
        return t;
    }
}
