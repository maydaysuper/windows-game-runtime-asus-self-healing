using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

public sealed class HealthScoreService
{
    private static readonly string[] AsusGroups = ["PV", "HOLTEK", "ENE"];

    public HealthScoreSnapshot Calculate(
        IReadOnlyCollection<ComponentItem> components,
        bool brokerValid,
        IReadOnlyCollection<CrashEventItem> recentCrashGroups)
    {
        var asus = components.Where(x => AsusGroups.Contains(x.Group, StringComparer.OrdinalIgnoreCase)).ToArray();
        var runtime = components.Where(x => x.Group.Equals("RUNTIME", StringComparison.OrdinalIgnoreCase)).ToArray();

        var asusSevere = CountSevere(asus);
        var asusWarn = CountWarn(asus);
        var runtimeSevere = CountSevere(runtime);
        var runtimeWarn = CountWarn(runtime);
        var crashFail = recentCrashGroups.Count(x => x.Severity.Equals("FAIL", StringComparison.OrdinalIgnoreCase));
        var crashWarn = recentCrashGroups.Count(x => x.Severity.Equals("WARN", StringComparison.OrdinalIgnoreCase));

        var score = 100;
        score -= Math.Min(32, asusSevere * 14 + asusWarn * 4);
        score -= Math.Min(28, runtimeSevere * 14 + runtimeWarn * 4);
        score -= Math.Min(22, crashFail * 5 + crashWarn * 2);
        if (!brokerValid) score -= 18;
        score = Math.Clamp(score, 0, 100);

        var state = score >= 90 ? "HEALTHY" : score >= 72 ? "WARN" : "NEEDS_REPAIR";
        var summary = score >= 90
            ? "整体正常，可以玩游戏"
            : score >= 72
                ? "大体正常，有少量需要关注的项目"
                : "有明确问题，建议先处理";

        var asusState = DomainState(asusSevere, asusWarn);
        var runtimeState = DomainState(runtimeSevere, runtimeWarn);
        var crashState = crashFail > 0 ? "FAIL" : crashWarn > 0 ? "WARN" : "PASS";
        var systemState = brokerValid ? "PASS" : "FAIL";

        return new HealthScoreSnapshot(
            score,
            state,
            summary,
            asusState,
            asusSevere > 0
                ? $"奥创有 {asusSevere} 项更新错误，请到奥创中心"
                : asusWarn > 0
                    ? $"奥创有 {asusWarn} 项需要关注，请到奥创中心"
                    : "没有奥创更新错误",
            runtimeState,
            DomainSummary(runtimeSevere, runtimeWarn, "运行库"),
            crashState,
            recentCrashGroups.Count == 0 ? "近 7 天没有游戏崩溃" : $"近 7 天有 {recentCrashGroups.Count} 组崩溃，其中严重 {crashFail} 次",
            systemState,
            brokerValid ? "系统保护正常" : "系统保护校验失败，修复功能已关闭");
    }

    private static int CountSevere(IEnumerable<ComponentItem> rows)
        => rows.Count(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");

    private static int CountWarn(IEnumerable<ComponentItem> rows)
        => rows.Count(x => x.Status is "WARN" or "UPDATE" or "ATTENTION");

    private static string DomainState(int severe, int warn)
        => severe > 0 ? "FAIL" : warn > 0 ? "WARN" : "PASS";

    private static string DomainSummary(int severe, int warn, string label)
        => severe > 0 ? $"{label}需要处理" : warn > 0 ? $"{label}需要关注" : $"{label}正常";
}
