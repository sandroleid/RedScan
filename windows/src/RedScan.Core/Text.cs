using System.Text;
using System.Text.RegularExpressions;

namespace RedScan.Core;

public static class Text
{
    /// <summary>Entfernt Steuerzeichen und kollabiert Whitespace.</summary>
    public static string Clean(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s)
            sb.Append((c >= 32 && c < 127) || (c > 160 && c != '�') ? c : ' ');
        return Regex.Replace(sb.ToString(), @"\s+", " ").Trim();
    }

    public static string DecodeEntities(string s)
    {
        var map = new (string, string)[]
        {
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&nbsp;", " "), ("&auml;", "ä"), ("&ouml;", "ö"), ("&uuml;", "ü"), ("&szlig;", "ß"),
        };
        foreach (var (k, v) in map) s = s.Replace(k, v);
        return s;
    }

    public static string? NilIfEmpty(this string? s) => string.IsNullOrEmpty(s) ? null : s;
}
