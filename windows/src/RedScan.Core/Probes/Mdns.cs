using System.Net;
using System.Net.Sockets;
using System.Text;

namespace RedScan.Core.Probes;

public static class Mdns
{
    public record Result(Dictionary<string, string> Hostnames, List<(string Ip, BonjourService Service)> Services);

    private static readonly IPAddress Group = IPAddress.Parse("224.0.0.251");
    private const int Port = 5353;

    /// <summary>Durchsucht das Netz per mDNS: löst Dienste (SRV/TXT/A) auf und fragt Reverse-PTR für jede IP.</summary>
    public static Result Browse(IReadOnlyList<string> ipsForReverse, double seconds = 4.0)
    {
        var hostnames = new Dictionary<string, string>();
        var services = new List<(string, BonjourService)>();

        Socket sock;
        try
        {
            sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            sock.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            sock.Bind(new IPEndPoint(IPAddress.Any, Port));
            try { sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.AddMembership, new MulticastOption(Group, IPAddress.Any)); } catch { }
            sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 4);
        }
        catch
        {
            // Port 5353 belegt → auf ephemeren Port ausweichen, Unicast-Antworten erbitten
            sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            sock.Bind(new IPEndPoint(IPAddress.Any, 0));
        }

        var groupEp = new IPEndPoint(Group, Port);
        // Diensttypen abfragen
        foreach (var type in BonjourTypes.Known.Keys)
        {
            var name = type.EndsWith(".") ? type + "local" : type + ".local";
            try { var q = DnsWire.BuildQuery(name, 12, true); sock.SendTo(q, groupEp); } catch { }
        }
        // Reverse-PTR je Host
        foreach (var ip in ipsForReverse)
        {
            var octets = ip.Split('.');
            Array.Reverse(octets);
            var rev = string.Join(".", octets) + ".in-addr.arpa";
            try { var q = DnsWire.BuildQuery(rev, 12, true); sock.SendTo(q, groupEp); } catch { }
        }

        // SRV→Host, A→IP, TXT→Dict sammeln, danach zusammenführen
        var srv = new List<(string Instance, string Host, int Port)>();
        var txt = new Dictionary<string, Dictionary<string, string>>();
        var aRecords = new Dictionary<string, string>(); // host(lower) → ip

        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        var buffer = new byte[65535];
        sock.ReceiveTimeout = 300;
        var ep = (EndPoint)new IPEndPoint(IPAddress.Any, 0);
        while (DateTime.UtcNow < deadline)
        {
            int n;
            try { n = sock.ReceiveFrom(buffer, ref ep); }
            catch (SocketException) { continue; }
            catch { break; }
            if (n <= 0) continue;
            var senderIp = ((IPEndPoint)ep).Address.ToString();
            var msg = new byte[n];
            Array.Copy(buffer, msg, n);
            ParseResponse(msg, senderIp, hostnames, srv, txt, aRecords);
        }
        try { sock.Dispose(); } catch { }

        // Dienste zusammensetzen
        foreach (var (instance, host, port) in srv)
        {
            string? type = KnownTypeOf(instance);
            if (type is null) continue;
            string ip = aRecords.GetValueOrDefault(host.ToLowerInvariant(), "");
            if (string.IsNullOrEmpty(ip)) continue;
            var svc = new BonjourService
            {
                Name = InstanceLabel(instance, type),
                Type = type,
                Port = port,
                HostName = host.TrimEnd('.'),
                Txt = txt.GetValueOrDefault(instance) ?? new Dictionary<string, string>()
            };
            services.Add((ip, svc));
        }
        return new Result(hostnames, services);
    }

    private static void ParseResponse(byte[] msg, string senderIp,
        Dictionary<string, string> hostnames,
        List<(string, string, int)> srv,
        Dictionary<string, Dictionary<string, string>> txt,
        Dictionary<string, string> aRecords)
    {
        foreach (var rec in DnsWire.ParseRecords(msg))
        {
            switch (rec.Type)
            {
                case 1: // A
                    if (rec.DataLen == 4)
                        aRecords[rec.Name.ToLowerInvariant()] = $"{rec.Data[rec.DataOffset]}.{rec.Data[rec.DataOffset + 1]}.{rec.Data[rec.DataOffset + 2]}.{rec.Data[rec.DataOffset + 3]}";
                    break;
                case 12: // PTR
                {
                    int o = rec.DataOffset;
                    var target = DnsWire.ReadName(rec.Data, ref o);
                    if (target != null)
                    {
                        if (rec.Name.EndsWith("in-addr.arpa"))
                        {
                            // Reverse: Name 4.3.2.1.in-addr.arpa → IP 1.2.3.4
                            var parts = rec.Name.Split('.');
                            if (parts.Length >= 4)
                            {
                                var ip = $"{parts[3]}.{parts[2]}.{parts[1]}.{parts[0]}";
                                if (!hostnames.ContainsKey(ip)) hostnames[ip] = target.Replace(".local", "").TrimEnd('.');
                            }
                        }
                    }
                    break;
                }
                case 16: // TXT
                {
                    var dict = new Dictionary<string, string>();
                    int p = rec.DataOffset, end = rec.DataOffset + rec.DataLen;
                    while (p < end)
                    {
                        int len = rec.Data[p]; p++;
                        if (len == 0 || p + len > end) break;
                        var entry = Encoding.UTF8.GetString(rec.Data, p, len);
                        p += len;
                        int eq = entry.IndexOf('=');
                        if (eq > 0) dict[entry[..eq]] = Text.Clean(entry[(eq + 1)..]);
                        else if (eq < 0) dict[entry] = "";
                    }
                    txt[rec.Name] = dict;
                    break;
                }
                case 33: // SRV
                {
                    if (rec.DataLen < 7) break;
                    int port = (rec.Data[rec.DataOffset + 4] << 8) | rec.Data[rec.DataOffset + 5];
                    int o = rec.DataOffset + 6;
                    var host = DnsWire.ReadName(rec.Data, ref o);
                    if (host != null) srv.Add((rec.Name, host, port));
                    break;
                }
            }
        }
    }

    private static string? KnownTypeOf(string instance)
    {
        foreach (var type in BonjourTypes.Known.Keys)
        {
            var needle = type.EndsWith(".") ? type : type + ".";
            if (instance.Contains(needle)) return type;
        }
        return null;
    }

    private static string InstanceLabel(string instance, string type)
    {
        var idx = instance.IndexOf("._", StringComparison.Ordinal);
        return idx > 0 ? instance[..idx] : instance;
    }
}
