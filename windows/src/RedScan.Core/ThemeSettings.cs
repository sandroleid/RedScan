using System.Text.Json;
using System.Text.Json.Nodes;

namespace RedScan.Core;

/// <summary>Darstellung der App.</summary>
public enum AppTheme { Dark, Light }

/// <summary>
/// Liest und speichert die gewählte Darstellung in <c>%LOCALAPPDATA%\RedScan\settings.json</c>
/// (z. B. <c>{ "theme": "dark" }</c>). Fehlende oder ungültige Datei → Dunkel.
/// </summary>
public static class ThemeSettings
{
    public static string DefaultPath { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RedScan", "settings.json");

    public static string ToKey(AppTheme theme) => theme == AppTheme.Light ? "light" : "dark";

    /// <summary>"light"/"dark" (Groß-/Kleinschreibung egal) → Theme, sonst null.</summary>
    public static AppTheme? Parse(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        "light" => AppTheme.Light,
        "dark" => AppTheme.Dark,
        _ => null,
    };

    /// <summary>Kommandozeile <c>--theme light|dark</c>; null, wenn nicht (gültig) angegeben.</summary>
    public static AppTheme? FromArgs(IReadOnlyList<string> args)
    {
        for (int i = 0; i < args.Count - 1; i++)
            if (string.Equals(args[i], "--theme", StringComparison.OrdinalIgnoreCase))
                return Parse(args[i + 1]);
        return null;
    }

    public static AppTheme Load(string path)
    {
        try
        {
            if (!File.Exists(path)) return AppTheme.Dark;
            var node = JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
            var value = node?["theme"] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
            return Parse(value) ?? AppTheme.Dark;
        }
        catch
        {
            return AppTheme.Dark;
        }
    }

    /// <summary>Speichert das Theme; andere Einträge in settings.json bleiben erhalten.</summary>
    public static void Save(string path, AppTheme theme)
    {
        JsonObject obj;
        try
        {
            obj = File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject o ? o : new JsonObject();
        }
        catch
        {
            obj = new JsonObject();
        }
        obj["theme"] = ToKey(theme);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllText(path, obj.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }
}
