using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.RegularExpressions;

namespace RedScan.Core.Probes;

public static class NetworkDetector
{
    public static NetworkInfo? Detect(string? customCidr = null)
    {
        NetworkInterface? chosen = null;
        UnicastIPAddressInformation? chosenAddr = null;

        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
            var props = ni.GetIPProperties();
            if (props.GatewayAddresses.All(g => g.Address.AddressFamily != AddressFamily.InterNetwork)) continue;
            var addr = props.UnicastAddresses.FirstOrDefault(u =>
                u.Address.AddressFamily == AddressFamily.InterNetwork && u.IPv4Mask != null && !IsApipa(u.Address));
            if (addr is null) continue;
            // Kabel bevorzugen, sonst erstes brauchbares Interface
            if (chosen is null || ni.NetworkInterfaceType == NetworkInterfaceType.Ethernet)
            {
                chosen = ni;
                chosenAddr = addr;
            }
        }

        if (chosen is null || chosenAddr is null) return null;
        var p = chosen.GetIPProperties();

        uint ip = IPv4.ToUInt32(chosenAddr.Address.ToString())!.Value;
        uint mask = IPv4.ToUInt32(chosenAddr.IPv4Mask!.ToString())!.Value;
        int prefix = IPv4.PrefixLength(mask);
        string cidr = $"{IPv4.ToString(ip & mask)}/{prefix}";
        string? note = null;

        if (prefix < 16)
        {
            cidr = $"{IPv4.ToString(ip & 0xFFFF0000)}/16";
            note = $"Sehr großes Netz (/{prefix}) – es wird das eigene /16 gescannt. Eigenes Ziel unten eintragen.";
        }

        if (!string.IsNullOrWhiteSpace(customCidr))
        {
            if (IPv4.Hosts(customCidr.Trim()) != null) { cidr = customCidr.Trim(); note = null; }
            else note = $"Ungültiges Ziel „{customCidr.Trim()}“ (erlaubt: /16 bis /32).";
        }

        var hosts = IPv4.Hosts(cidr) ?? new List<string>();
        if (note is null && hosts.Count > 1024)
            note = $"Großes Netz: {hosts.Count:N0} Adressen – der Ping-Sweep dauert ca. {hosts.Count / 2000 + 3} s.";

        var gw = p.GatewayAddresses.FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork)?.Address.ToString();
        var dns = p.DnsAddresses.Where(a => a.AddressFamily == AddressFamily.InterNetwork).Select(a => a.ToString()).Distinct().ToList();
        var macBytes = chosen.GetPhysicalAddress().GetAddressBytes();
        var mac = macBytes.Length == 6 ? IPv4.MacFromBytes(macBytes) : null;

        return new NetworkInfo
        {
            Interface = chosen.Name,
            Ip = IPv4.ToString(ip),
            Netmask = IPv4.ToString(mask),
            Prefix = prefix,
            Mac = mac,
            Gateway = gw,
            Dns = dns,
            Ssid = chosen.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 ? WifiSsid() : null,
            Cidr = cidr,
            Hosts = hosts,
            Note = note
        };
    }

    private static bool IsApipa(IPAddress a)
    {
        var b = a.GetAddressBytes();
        return b[0] == 169 && b[1] == 254;
    }

    private static string? WifiSsid()
    {
        try
        {
            var psi = new ProcessStartInfo("netsh", "wlan show interfaces")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            if (proc is null) return null;
            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit(2000);
            var m = Regex.Match(output, @"^\s*SSID\s*:\s*(.+)$", RegexOptions.Multiline);
            return m.Success ? m.Groups[1].Value.Trim() : null;
        }
        catch { return null; }
    }
}
