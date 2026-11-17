using System.Net;
using System.Net.Sockets;
using System.Text;

namespace RedScan.Core.Probes;

/// <summary>NetBIOS-Namensabfrage (UDP 137) für Windows-/Samba-Namen.</summary>
public static class NetBios
{
    public record Result(string? Name, string? Group, string? Mac);

    public static Dictionary<string, Result> Query(IReadOnlyList<string> ips, double seconds = 2.0)
    {
        var results = new Dictionary<string, Result>();
        using var sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        sock.Bind(new IPEndPoint(IPAddress.Any, 0));

        // Node-Status-Abfrage für "*"
        var q = new List<byte> { 0x13, 0x37, 0x00, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0x20 };
        var name = new byte[16];
        name[0] = 0x2A; // '*'
        foreach (var bb in name) { q.Add((byte)(0x41 + (bb >> 4))); q.Add((byte)(0x41 + (bb & 0x0F))); }
        q.AddRange(new byte[] { 0x00, 0x00, 0x21, 0x00, 0x01 });
        var query = q.ToArray();

        foreach (var ip in ips)
            try { sock.SendTo(query, new IPEndPoint(IPAddress.Parse(ip), 137)); } catch { }

        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        var buffer = new byte[2048];
        sock.ReceiveTimeout = 300;
        var ep = (EndPoint)new IPEndPoint(IPAddress.Any, 0);
        while (DateTime.UtcNow < deadline)
        {
            int n;
            try { n = sock.ReceiveFrom(buffer, ref ep); }
            catch (SocketException) { continue; }
            catch { break; }
            if (n <= 57) continue;
            int num = buffer[56];
            if (n < 57 + num * 18) continue;
            string? nbName = null, nbGroup = null, mac = null;
            for (int i = 0; i < num; i++)
            {
                int o = 57 + i * 18;
                var nm = Encoding.ASCII.GetString(buffer, o, 15).Trim().Trim('\0');
                byte suffix = buffer[o + 15];
                bool isGroup = (buffer[o + 16] & 0x80) != 0;
                if (suffix == 0x00 && !isGroup && nbName is null) nbName = nm;
                if (suffix == 0x00 && isGroup && nbGroup is null) nbGroup = nm;
            }
            int macOff = 57 + num * 18;
            if (n >= macOff + 6)
            {
                var mb = new byte[6];
                Array.Copy(buffer, macOff, mb, 0, 6);
                var m = IPv4.MacFromBytes(mb);
                if (m != "00:00:00:00:00:00") mac = m;
            }
            results[((IPEndPoint)ep).Address.ToString()] = new Result(nbName, nbGroup, mac);
        }
        return results;
    }
}
