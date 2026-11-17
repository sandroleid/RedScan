using Microsoft.UI.Xaml;

namespace RedScan.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "RedScan – Netzwerk-Scanner";
        try { AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 880)); } catch { }

        // Unverpackte WinUI-Apps übernehmen das EXE-Icon nicht automatisch für Fenster und Taskleiste.
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "RedScan.ico");
        if (File.Exists(icon))
        {
            try { AppWindow.SetIcon(icon); App.Log("Fenster-Icon gesetzt"); }
            catch (Exception ex) { App.Log("Fenster-Icon konnte nicht gesetzt werden: " + ex.Message); }
        }
        else
        {
            App.Log("FEHLER: Icon-Datei fehlt: " + icon);
        }
    }
}
