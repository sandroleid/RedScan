using System.Net;

namespace RedScan.Core;

/// <summary>IPv4-Hilfen: Umrechnung, Netzmasken, Host-Aufzählung.</summary>
public static class IPv4
{
    public static uint? ToUInt32(string s)
    {
        if (!IPAddress.TryParse(s, out var ip) || ip.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork)
            return null;
        var b = ip.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3];
    }

    public static string ToString(uint v) => $"{v >> 24 & 0xff}.{v >> 16 & 0xff}.{v >> 8 & 0xff}.{v & 0xff}";

    /// <summary>Wandelt eine IPv4 im Windows-Netzwerk-Byteorder-Format (little-endian uint) in Text.</summary>
    public static string FromNetworkOrder(uint netOrder)
    {
        return $"{netOrder & 0xff}.{netOrder >> 8 & 0xff}.{netOrder >> 16 & 0xff}.{netOrder >> 24 & 0xff}";
    }

    public static int PrefixLength(uint mask)
    {
        int c = 0;
        while (mask != 0) { c += (int)(mask & 1); mask >>= 1; }
        return c;
    }

    public static uint MaskFromPrefix(int prefix) => prefix == 0 ? 0u : ~0u << (32 - prefix);

    /// <summary>Host-Adressen eines Netzes "a.b.c.d/n" (ohne Netz- und Broadcast-Adresse).</summary>
    public static List<string>? Hosts(string cidr, int limit = 65534)
    {
        var parts = cidr.Trim().Split('/');
        var baseIp = ToUInt32(parts[0]);
        if (baseIp is null) return null;
        int prefix = parts.Length > 1 ? (int.TryParse(parts[1], out var p) ? p : 32) : 32;
        if (prefix < 16 || prefix > 32) return null;
        if (prefix >= 31) return new List<string> { ToString(baseIp.Value) };
        uint mask = MaskFromPrefix(prefix);
        uint net = baseIp.Value & mask;
        uint bcast = net | ~mask;
        long count = (long)bcast - net - 1;
        if (count < 1 || count > limit) return null;
        var list = new List<string>((int)count);
        for (uint i = 1; i <= count; i++) list.Add(ToString(net + i));
        return list;
    }

    public static string NormalizeMac(string raw)
    {
        var parts = raw.Replace('-', ':').Split(':');
        return string.Join(":", parts.Select(x => x.Length == 1 ? "0" + x : x)).ToUpperInvariant();
    }

    public static string MacFromBytes(byte[] b, int len = 6) =>
        string.Join(":", b.Take(len).Select(x => x.ToString("X2")));
}
