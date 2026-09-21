using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Controls;

public enum InfoBarSeverity
{
    Informational,
    Success,
    Warning,
    Error
}

public sealed class StatusBanner : Border
{
    private readonly TextBlock _title = new() { FontSize = 14, FontWeight = FontWeights.SemiBold };
    private readonly TextBlock _message = new() { FontSize = 13, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
    private InfoBarSeverity _severity = InfoBarSeverity.Informational;

    public StatusBanner()
    {
        Padding = new Thickness(14, 10, 14, 10);
        CornerRadius = new CornerRadius(8);
        Margin = new Thickness(0, 16, 0, 0);
        Child = new StackPanel { Children = { _title, _message } };
        Apply();
    }

    public string Title { get => _title.Text; set => _title.Text = value ?? ""; }
    public string Message { get => _message.Text; set => _message.Text = value ?? ""; }
    public bool IsOpen
    {
        get => Visibility == Visibility.Visible;
        set => Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }
    public InfoBarSeverity Severity
    {
        get => _severity;
        set { _severity = value; Apply(); }
    }

    private void Apply()
    {
        Background = new SolidColorBrush(_severity switch
        {
            InfoBarSeverity.Success => Color.FromRgb(220, 252, 231),
            InfoBarSeverity.Warning => Color.FromRgb(254, 243, 199),
            InfoBarSeverity.Error => Color.FromRgb(254, 226, 226),
            _ => Color.FromRgb(219, 234, 254)
        });
        var fg = _severity switch
        {
            InfoBarSeverity.Success => Color.FromRgb(22, 101, 52),
            InfoBarSeverity.Warning => Color.FromRgb(146, 64, 14),
            InfoBarSeverity.Error => Color.FromRgb(153, 27, 27),
            _ => Color.FromRgb(30, 64, 175)
        };
        _title.Foreground = new SolidColorBrush(fg);
        _message.Foreground = new SolidColorBrush(Color.FromRgb(51, 65, 85));
    }
}
