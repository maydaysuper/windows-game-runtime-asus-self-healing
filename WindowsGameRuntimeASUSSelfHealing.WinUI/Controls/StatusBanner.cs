using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace WindowsGameRuntimeASUSSelfHealing.WinUI.Controls;

/// <summary>
/// Primitive stand-in for InfoBar. Templated WinUI controls FailFast on unpackaged WASDK 2.x
/// when generic.xaml is not in the MRT graph; a Grid does not.
/// </summary>
public sealed class StatusBanner : Grid
{
    private readonly TextBlock _title = new() { FontSize = 14, FontWeight = new FontWeight { Weight = 600 } };
    private readonly TextBlock _message = new() { FontSize = 13, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };
    private InfoBarSeverity _severity = InfoBarSeverity.Informational;
    private bool _open = true;

    public StatusBanner()
    {
        Padding = new Thickness(14, 10, 14, 10);
        CornerRadius = new CornerRadius(8);
        Children.Add(new StackPanel { Children = { _title, _message } });
        Apply();
    }

    public string Title { get => _title.Text; set => _title.Text = value ?? ""; }
    public string Message { get => _message.Text; set => _message.Text = value ?? ""; }
    public bool IsOpen
    {
        get => _open;
        set
        {
            _open = value;
            Visibility = value ? Visibility.Visible : Visibility.Collapsed;
        }
    }
    public InfoBarSeverity Severity
    {
        get => _severity;
        set { _severity = value; Apply(); }
    }

    private void Apply()
    {
        var color = _severity switch
        {
            InfoBarSeverity.Success => ColorHelper.FromArgb(255, 220, 252, 231),
            InfoBarSeverity.Warning => ColorHelper.FromArgb(255, 254, 243, 199),
            InfoBarSeverity.Error => ColorHelper.FromArgb(255, 254, 226, 226),
            _ => ColorHelper.FromArgb(255, 219, 234, 254)
        };
        Background = new SolidColorBrush(color);
    }
}
