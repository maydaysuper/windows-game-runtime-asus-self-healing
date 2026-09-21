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
            if (!string.IsNullOrWhiteSpace(Error) && HasEvidence) return "WARN";
            if (!HasEvidence) return "INFO";
            return "WARN";
        }
    }

    public string Summary
    {
        get
        {
            if (Success && TrustComplete)
            {
                var bits = new List<string>();
                if (!string.IsNullOrWhiteSpace(Version)) bits.Add(Version);
                if (!string.IsNullOrWhiteSpace(Signer)) bits.Add(Signer);
                if (!string.IsNullOrWhiteSpace(Source)) bits.Add(Source);
                return bits.Count == 0 ? "Microsoft 官方包签名与来源校验通过" : string.Join(" · ", bits);
            }
            if (!string.IsNullOrWhiteSpace(Error)) return Error;
            if (!HasEvidence)
                return "尚未拿到完整的 Microsoft 官方包证据。本地 VC++ / DirectX 仍以上方运行库状态为准，不把这次空结果当成故障。";
            return "官方包证据不完整，未通过签名/来源校验。";
        }
    }

    public Brush StatusBrush => StatusPalette.Brush(Status);
    public Brush StatusForeground => StatusPalette.Foreground(Status);
}
