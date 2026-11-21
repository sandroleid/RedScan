using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using RedScan.Core;
using Windows.UI;

namespace RedScan.App;

/// <summary>
/// Aktuelle Darstellung (Hell/Dunkel). Start: --theme (nur für diesen Start) oder gespeicherter Wert.
/// Wechsel wirkt sofort über RequestedTheme am Wurzelelement (ThemeResource) und das Changed-Ereignis.
/// </summary>
public static class ThemeService
{
    public static AppTheme Current { get; private set; } = AppTheme.Dark;
    public static bool IsLight => Current == AppTheme.Light;
    public static ElementTheme ElementTheme => IsLight ? ElementTheme.Light : ElementTheme.Dark;

    public static event Action? Changed;

    public static void Initialize(string[] args)
    {
        var fromArgs = ThemeSettings.FromArgs(args);
        Current = fromArgs ?? ThemeSettings.Load(ThemeSettings.DefaultPath);
        App.Log($"Darstellung: {Label(Current)}" + (fromArgs != null ? " (Kommandozeile)" : ""));
    }

    public static void Set(AppTheme theme)
    {
        if (theme == Current) return;
        Current = theme;
        try { ThemeSettings.Save(ThemeSettings.DefaultPath, theme); }
        catch (Exception ex) { App.Log("Darstellung konnte nicht gespeichert werden: " + ex.Message); }
        App.Log("Darstellung gewechselt: " + Label(theme));
        Changed?.Invoke();
    }

    private static string Label(AppTheme t) => t == AppTheme.Light ? "hell" : "dunkel";
}

/// <summary>Farb-Tokens für Code (Titelleiste, x:Bind-Funktionen). XAML nutzt die ThemeResources aus App.xaml.</summary>
public static class Palette
{
    public static readonly Color White = Color.FromArgb(255, 255, 255, 255);
    private static readonly Color LightText = Color.FromArgb(255, 0x1A, 0x0F, 0x11);

    public static Color Text(bool light) => light ? LightText : White;
    public static Color Dim(bool light) => light ? Color.FromArgb(0x9E, 0x1A, 0x0F, 0x11) : Color.FromArgb(0x8C, 255, 255, 255);

    // x:Bind-Funktionen für Segment-Buttons (Text auf rotem Verlauf bleibt immer weiß)

    /// <summary>Tabs „Geräte | Verlauf“: aktiv weiß, sonst Primärtext (Dunkel unverändert weiß).</summary>
    public static Brush NavForeground(bool active, bool light) => new SolidColorBrush(active ? White : Text(light));

    /// <summary>Umschalter „Dunkel | Hell“: aktiv weiß, sonst Dim.</summary>
    public static Brush SegmentForeground(bool active, bool light) => new SolidColorBrush(active ? White : Dim(light));
}
