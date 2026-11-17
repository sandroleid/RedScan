using Microsoft.UI.Xaml;

namespace RedScan.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "RedScan – Netzwerk-Scanner";
        try { AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 880)); } catch { }
    }
}
