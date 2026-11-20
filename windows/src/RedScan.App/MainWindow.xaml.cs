using Microsoft.UI.Xaml;

namespace RedScan.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "RedScan – Netzwerk-Scanner";
        try { AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 880)); } catch { }

        // Weißen System-Titelbalken durch eigene dunkle Leiste ersetzen
        try
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);
            var tb = AppWindow.TitleBar;
            var white = Windows.UI.Color.FromArgb(255, 255, 255, 255);
            var dim = Windows.UI.Color.FromArgb(140, 255, 255, 255);
            var clear = Windows.UI.Color.FromArgb(0, 0, 0, 0);
            tb.ButtonBackgroundColor = clear;
            tb.ButtonInactiveBackgroundColor = clear;
            tb.ButtonForegroundColor = white;
            tb.ButtonInactiveForegroundColor = dim;
            tb.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(40, 255, 255, 255);
            tb.ButtonHoverForegroundColor = white;
            tb.ButtonPressedBackgroundColor = Windows.UI.Color.FromArgb(70, 232, 34, 48);
            tb.ButtonPressedForegroundColor = white;
            App.Log("Titelleiste angepasst");
        }
        catch (Exception ex) { App.Log("Titelleiste konnte nicht angepasst werden: " + ex.Message); }

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
