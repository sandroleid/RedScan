using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace RedScan.App;

public sealed partial class DetailRow : UserControl
{
    public DetailRow()
    {
        InitializeComponent();
    }

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }
    public static readonly DependencyProperty LabelProperty =
        DependencyProperty.Register(nameof(Label), typeof(string), typeof(DetailRow),
            new PropertyMetadata("", (d, _) => ((DetailRow)d).Apply()));

    public string? Value
    {
        get => (string?)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }
    public static readonly DependencyProperty ValueProperty =
        DependencyProperty.Register(nameof(Value), typeof(string), typeof(DetailRow),
            new PropertyMetadata(null, (d, _) => ((DetailRow)d).Apply()));

    public bool Mono
    {
        get => (bool)GetValue(MonoProperty);
        set => SetValue(MonoProperty, value);
    }
    public static readonly DependencyProperty MonoProperty =
        DependencyProperty.Register(nameof(Mono), typeof(bool), typeof(DetailRow),
            new PropertyMetadata(false, (d, _) => ((DetailRow)d).Apply()));

    private void Apply()
    {
        LabelText.Text = Label;
        ValueText.Text = Value ?? "";
        ValueText.FontFamily = Mono ? new FontFamily("Consolas") : FontFamily;
        Visibility = string.IsNullOrEmpty(Value) ? Visibility.Collapsed : Visibility.Visible;
    }
}
