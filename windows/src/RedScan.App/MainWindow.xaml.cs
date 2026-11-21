using Microsoft.UI.Xaml;
using Windows.UI;

namespace RedScan.App;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "RedScan – Netzwerk-Scanner";
        try { AppWindow.Resize(new Windows.Graphics.SizeInt32(1400, 880)); } catch { }

        // Darstellung (Hell/Dunkel) am Wurzelelement – alle ThemeResources folgen sofort
        RootGrid.RequestedTheme = ThemeService.ElementTheme;

        // Weißen System-Titelbalken durch eigene Leiste in App-Farben ersetzen
        try
        {
            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);
            ApplyCaptionColors();
            App.Log("Titelleiste angepasst");
        }
        catch (Exception ex) { App.Log("Titelleiste konnte nicht angepasst werden: " + ex.Message); }

        ThemeService.Changed += OnThemeChanged;
        Closed += (_, _) => ThemeService.Changed -= OnThemeChanged;

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

    private void OnThemeChanged()
    {
        RootGrid.RequestedTheme = ThemeService.ElementTheme;
        try { ApplyCaptionColors(); }
        catch (Exception ex) { App.Log("Titelleiste konnte nicht umgefärbt werden: " + ex.Message); }
    }

    /// <summary>Minimieren/Maximieren/Schließen passend zur Darstellung einfärben.</summary>
    private void ApplyCaptionColors()
    {
        bool light = ThemeService.IsLight;
        var tb = AppWindow.TitleBar;
        var fg = Palette.Text(light);
        var clear = Color.FromArgb(0, 0, 0, 0);
        tb.ButtonBackgroundColor = clear;
        tb.ButtonInactiveBackgroundColor = clear;
        tb.ButtonForegroundColor = fg;
        tb.ButtonInactiveForegroundColor = Palette.Dim(light);
        tb.ButtonHoverBackgroundColor = light ? Color.FromArgb(26, 0x1A, 0x0F, 0x11) : Color.FromArgb(40, 255, 255, 255);
        tb.ButtonHoverForegroundColor = fg;
        tb.ButtonPressedBackgroundColor = light ? Color.FromArgb(40, 232, 34, 48) : Color.FromArgb(70, 232, 34, 48);
        tb.ButtonPressedForegroundColor = fg;
    }
}
