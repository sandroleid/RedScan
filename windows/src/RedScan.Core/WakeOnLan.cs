using System.Net;
using System.Net.Sockets;

namespace RedScan.Core;

public static class WakeOnLan
{
    /// <summary>Baut das "Magic Packet" (6× 0xFF + 16× MAC). Gibt null bei ungültiger MAC zurück.</summary>
    public static byte[]? BuildPacket(string mac)
    {
        var hex = mac.Replace(":", "").Replace("-", "");
        if (hex.Length != 12) return null;
        var bytes = new byte[6];
        for (int i = 0; i < 6; i++)
            if (!byte.TryParse(hex.AsSpan(i * 2, 2), System.Globalization.NumberStyles.HexNumber, null, out bytes[i]))
                return null;
        var packet = new byte[102];
        for (int i = 0; i < 6; i++) packet[i] = 0xFF;
        for (int r = 0; r < 16; r++) Array.Copy(bytes, 0, packet, 6 + r * 6, 6);
        return packet;
    }

    /// <summary>Sendet das Magic Packet als UDP-Broadcast an Port 9 und 7.</summary>
    public static bool Wake(string mac, IEnumerable<string> broadcasts)
    {
        var packet = BuildPacket(mac);
        if (packet is null) return false;
        using var client = new UdpClient { EnableBroadcast = true };
        var targets = broadcasts.Append("255.255.255.255").Distinct();
        foreach (var t in targets)
        {
            if (!IPAddress.TryParse(t, out var addr)) continue;
            foreach (var port in new[] { 9, 7 })
                for (int i = 0; i < 3; i++)
                    try { client.Send(packet, packet.Length, new IPEndPoint(addr, port)); } catch { }
        }
        return true;
    }

    public static string? Broadcast(NetworkInfo net)
    {
        var ip = IPv4.ToUInt32(net.Ip);
        var mask = IPv4.ToUInt32(net.Netmask);
        if (ip is null || mask is null) return null;
        return IPv4.ToString(ip.Value | ~mask.Value);
    }
}
