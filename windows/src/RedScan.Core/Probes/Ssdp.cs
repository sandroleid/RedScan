using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Xml.Linq;

namespace RedScan.Core.Probes;

public static class Ssdp
{
    public record Response(string Ip, Dictionary<string, string> Headers);

    public static List<Response> Discover(double seconds = 3.5)
    {
        var results = new List<Response>();
        using var sock = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        sock.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        sock.Bind(new IPEndPoint(IPAddress.Any, 0));
        sock.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 4);
        var target = new IPEndPoint(IPAddress.Parse("239.255.255.250"), 1900);

        foreach (var st in new[] { "ssdp:all", "upnp:rootdevice" })
        {
            var msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\n" +
                      $"ST: {st}\r\n\r\n";
            var bytes = Encoding.ASCII.GetBytes(msg);
            for (int i = 0; i < 2; i++) try { sock.SendTo(bytes, target); } catch { }
        }

        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        var buffer = new byte[8192];
        sock.ReceiveTimeout = 300;
        var ep = (EndPoint)new IPEndPoint(IPAddress.Any, 0);
        while (DateTime.UtcNow < deadline)
        {
            int n;
            try { n = sock.ReceiveFrom(buffer, ref ep); }
            catch (SocketException) { continue; }
            catch { break; }
            if (n <= 0) continue;
            var text = Encoding.UTF8.GetString(buffer, 0, n);
            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var line in text.Split("\r\n"))
            {
                int c = line.IndexOf(':');
                if (c <= 0) continue;
                headers[line[..c].Trim().ToUpperInvariant()] = line[(c + 1)..].Trim();
            }
            results.Add(new Response(((IPEndPoint)ep).Address.ToString(), headers));
        }
        return results;
    }

    public static async Task<UPnPInfo> DescribeAsync(string location, string? server)
    {
        var info = new UPnPInfo { Location = location, Server = server };
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };
            client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "RedScan/1.0 UPnP/1.1");
            var xml = await client.GetStringAsync(location).ConfigureAwait(false);
            var doc = XDocument.Parse(xml);
            string? Find(string local) => doc.Descendants().FirstOrDefault(e => e.Name.LocalName == local)?.Value.Trim().NilIfEmpty();
            info.FriendlyName = Find("friendlyName");
            info.Manufacturer = Find("manufacturer");
            info.ModelName = Find("modelName");
            info.ModelNumber = Find("modelNumber");
            info.ModelDescription = Find("modelDescription");
            info.SerialNumber = Find("serialNumber");
            info.DeviceType = Find("deviceType");
            info.PresentationUrl = Find("presentationURL");
        }
        catch { }
        return info;
    }
}
