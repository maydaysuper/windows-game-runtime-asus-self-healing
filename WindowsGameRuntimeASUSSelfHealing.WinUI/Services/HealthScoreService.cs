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
            ? "系统游戏运行环境整体状态良好"
            : score >= 72
                ? "发现少量需要关注的问题"
                : "发现明确的修复或崩溃风险";

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
                ? $"奥创有 {asusSevere} 项更新/组件错误，详情到奥创中心"
                : asusWarn > 0
                    ? $"奥创有 {asusWarn} 项需要关注，详情到奥创中心"
                    : "当前没有奥创 4151/4152 更新错误",
            runtimeState,
            DomainSummary(runtimeSevere, runtimeWarn, "运行库"),
            crashState,
            recentCrashGroups.Count == 0 ? "近 7 天缓存中未发现崩溃组" : $"近 7 天 {recentCrashGroups.Count} 个崩溃组，其中严重 {crashFail} 个",
            systemState,
            brokerValid ? "安全门禁与 Broker 完整性正常" : "安全门禁校验失败，修复功能已受限");
    }

    private static int CountSevere(IEnumerable<ComponentItem> rows)
        => rows.Count(x => x.Status is "FAIL" or "REPAIR" or "NEEDS_REPAIR");

    private static int CountWarn(IEnumerable<ComponentItem> rows)
        => rows.Count(x => x.Status is "WARN" or "UPDATE" or "ATTENTION");

    private static string DomainState(int severe, int warn)
        => severe > 0 ? "FAIL" : warn > 0 ? "WARN" : "PASS";

    private static string DomainSummary(int severe, int warn, string label)
        => severe > 0 ? $"{label}有 {severe} 项需要修复" : warn > 0 ? $"{label}有 {warn} 项需要关注" : $"{label}当前正常";
}
