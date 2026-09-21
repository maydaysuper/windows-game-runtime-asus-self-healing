using System.Text.Json;
using System.Windows;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Models;
using WindowsGameRuntimeASUSSelfHealing.WinUI.Services;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Pages;

internal static class PageHelpers
{
    public static ComponentItem ToComponent(JsonElement e) => new()
    {
        Key = e.String("Key"),
        Name = e.String("Name"),
        Installed = e.String("Installed"),
        Target = e.String("Target"),
        Runtime = e.String("Runtime"),
        ErrorCode = e.String("ErrorCode"),
        Status = e.String("Status"),
        Detail = e.String("Detail"),
        Group = e.String("Group")
    };

    public static PreflightItem ToPreflight(JsonElement e) => new()
    {
        Name = e.String("Name"), Status = e.String("Status"), Detail = e.String("Detail"), Blocking = e.Bool("Blocking")
    };

    public static TransactionItem ToTransaction(JsonElement e) => new()
    {
        TransactionId = e.String("TransactionId"), Type = e.String("Type"), Group = e.String("Group"), Label = e.String("Label"),
        State = e.String("State"), StartedAt = e.String("StartedAt"), UpdatedAt = e.String("UpdatedAt"), LastDetail = e.String("LastDetail")
    };

    public static Task ShowAsync(FrameworkElement owner, string title, string content, string closeText = "确定")
    {
        _ = owner;
        _ = closeText;
        MessageBox.Show(Window.GetWindow(owner), content, title, MessageBoxButton.OK, MessageBoxImage.Information);
        return Task.CompletedTask;
    }

    public static Task<bool> ConfirmAsync(FrameworkElement owner, string title, string content, string primary = "继续")
    {
        _ = primary;
        var result = MessageBox.Show(Window.GetWindow(owner), content, title, MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        return Task.FromResult(result == MessageBoxResult.OK);
    }
}
