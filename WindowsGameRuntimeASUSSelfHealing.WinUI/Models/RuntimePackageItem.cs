using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

public sealed class RuntimePackageItem
{
    public string Key { get; init; } = "";
    public string Version { get; init; } = "";
    public string Source { get; init; } = "";
    public string Sha256 { get; init; } = "";
    public string Signer { get; init; } = "";
    public string FinalUri { get; init; } = "";
    public string Error { get; init; } = "";
    public bool Success { get; init; }
    public bool TrustComplete { get; init; }

    public bool HasEvidence =>
        !string.IsNullOrWhiteSpace(Version)
        || !string.IsNullOrWhiteSpace(Signer)
        || !string.IsNullOrWhiteSpace(FinalUri)
        || !string.IsNullOrWhiteSpace(Sha256);

    public string Status
    {
        get
        {
            if (Success && TrustComplete) return "PASS";
            if (HasEvidence && (!Success || !TrustComplete)) return "WARN";
            return "INFO";
        }
    }

    public string Verdict => Success && TrustComplete
        ? "不必修复"
        : HasEvidence
            ? "需要关注"
            : "不必修复";

    public string Summary
    {
        get
        {
            if (Success && TrustComplete)
            {
                var bits = new List<string> { "结论：不必修复" };
                if (!string.IsNullOrWhiteSpace(Version)) bits.Add(Version);
                if (!string.IsNullOrWhiteSpace(Signer)) bits.Add(Signer);
                return string.Join(" · ", bits);
            }

            var err = FriendlyError(Error);
            if (!HasEvidence)
                return string.IsNullOrWhiteSpace(err)
                    ? "结论：不必修复。官方安装器这次没取到，以上方本机 VC++ / DirectX 状态为准。"
                    : "结论：不必修复。" + err;
            return string.IsNullOrWhiteSpace(err)
                ? "结论：需要关注。官方包证据不完整。"
                : "结论：需要关注。" + err;
        }
    }

    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);

    private static string FriendlyError(string error)
    {
        if (string.IsNullOrWhiteSpace(error)) return "";
        if (error.Contains("Host", StringComparison.OrdinalIgnoreCase) && error.Contains("只读"))
            return "官方包下载器变量冲突已在本版修复，请再点一次「联网对比」。";
        return error;
    }
}
