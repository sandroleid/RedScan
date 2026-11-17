using System.Reflection;

namespace RedScan.Core;

/// <summary>Hersteller-Datenbank aus der eingebetteten oui.txt (Wireshark-'manuf').</summary>
public sealed class VendorDb
{
    public static readonly VendorDb Shared = new();

    private readonly Dictionary<string, string> _table = new();
    public int Count => _table.Count;

    private VendorDb()
    {
        var asm = Assembly.GetExecutingAssembly();
        var name = asm.GetManifestResourceNames().FirstOrDefault(n => n.EndsWith("oui.txt"));
        if (name is null) return;
        using var stream = asm.GetManifestResourceStream(name);
        if (stream is null) return;
        using var reader = new StreamReader(stream);
        string? line;
        while ((line = reader.ReadLine()) != null)
        {
            int tab = line.IndexOf('\t');
            if (tab <= 0) continue;
            _table[line[..tab]] = line[(tab + 1)..];
        }
    }

    public string? Lookup(string? mac)
    {
        if (string.IsNullOrEmpty(mac)) return null;
        var hex = mac.Replace(":", "").Replace("-", "").ToUpperInvariant();
        foreach (var n in new[] { 9, 7, 6 })
            if (hex.Length >= n && _table.TryGetValue(hex[..n], out var v)) return v;
        return null;
    }

    /// <summary>Lokal verwaltete (meist zufällige/private) MAC-Adresse?</summary>
    public static bool IsRandomized(string mac)
    {
        if (mac.Length < 2 || !byte.TryParse(mac.AsSpan(0, 2), System.Globalization.NumberStyles.HexNumber, null, out var first))
            return false;
        return (first & 0x02) != 0;
    }
}
