using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Text.Json;
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

    public static async Task ShowAsync(FrameworkElement owner, string title, string content, string closeText = "确定")
    {
        var dlg = new ContentDialog { XamlRoot = owner.XamlRoot, Title = title, Content = content, CloseButtonText = closeText };
        await dlg.ShowAsync();
    }

    public static async Task<bool> ConfirmAsync(FrameworkElement owner, string title, string content, string primary = "继续")
    {
        var dlg = new ContentDialog
        {
            XamlRoot = owner.XamlRoot,
            Title = title,
            Content = new ScrollViewer { MaxHeight = 520, Content = new TextBlock { Text = content, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true } },
            PrimaryButtonText = primary,
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close
        };
        return await dlg.ShowAsync() == ContentDialogResult.Primary;
    }
}
