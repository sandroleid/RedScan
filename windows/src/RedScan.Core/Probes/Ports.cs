using System.Net;
using System.Net.Sockets;
using System.Text;

namespace RedScan.Core.Probes;

public static class Ports
{
    public static readonly Dictionary<int, string> Names = new()
    {
        [20] = "FTP-Daten", [21] = "FTP", [22] = "SSH", [23] = "Telnet", [25] = "SMTP", [53] = "DNS", [80] = "HTTP", [81] = "HTTP-Alt",
        [88] = "Kerberos", [110] = "POP3", [111] = "RPC", [135] = "MS-RPC", [139] = "NetBIOS-Session", [143] = "IMAP", [389] = "LDAP",
        [443] = "HTTPS", [445] = "SMB (Dateifreigabe)", [465] = "SMTPS", [515] = "LPD (Drucker)", [548] = "AFP (Apple-Freigabe)",
        [554] = "RTSP (Kamera/Stream)", [587] = "SMTP-Submission", [631] = "IPP (Drucker)", [853] = "DNS-over-TLS", [993] = "IMAPS",
        [995] = "POP3S", [1080] = "SOCKS-Proxy", [1400] = "Sonos", [1433] = "MS-SQL", [1521] = "Oracle DB", [1723] = "PPTP-VPN",
        [1883] = "MQTT (IoT)", [2049] = "NFS", [2375] = "Docker-API", [3000] = "Web-App", [3306] = "MySQL", [3389] = "RDP (Remotedesktop)",
        [3689] = "DAAP (iTunes)", [4070] = "Spotify Connect", [5000] = "UPnP / Web", [5001] = "Synology DSM", [5060] = "SIP (VoIP)",
        [5222] = "XMPP", [5357] = "WSD (Windows)", [5432] = "PostgreSQL", [5555] = "ADB (Android Debug)", [5900] = "VNC",
        [6379] = "Redis", [6443] = "Kubernetes", [6668] = "Tuya (Smart Home)", [7000] = "AirPlay", [7100] = "AirPlay-Screen",
        [8000] = "HTTP-Alt", [8008] = "Chromecast", [8009] = "Chromecast", [8060] = "Roku", [8080] = "HTTP-Proxy", [8081] = "HTTP-Alt",
        [8123] = "Home Assistant", [8291] = "MikroTik Winbox", [8443] = "HTTPS-Alt", [8888] = "HTTP-Alt", [9000] = "Web-Admin",
        [9090] = "Web-Admin", [9100] = "JetDirect (Drucker)", [9200] = "Elasticsearch", [10000] = "Webmin", [32400] = "Plex",
        [49000] = "FRITZ!Box TR-064", [49152] = "UPnP", [62078] = "iPhone/iPad-Sync",
    };

    public static List<int> Common => Names.Keys.OrderBy(x => x).ToList();

    public static List<int> Deep
    {
        get
        {
            var set = new HashSet<int>(Common);
            for (int i = 1; i <= 1024; i++) set.Add(i);
            foreach (var p in new[] { 1900, 2000, 2869, 3001, 4000, 4443, 5353, 7443, 8001, 8002, 8082, 8088, 8090, 8181, 8200, 8880, 9001, 9443, 10001, 37777, 50000 })
                set.Add(p);
            return set.OrderBy(x => x).ToList();
        }
    }

    public static readonly HashSet<int> HttpPorts = new() { 80, 81, 3000, 5000, 8000, 8008, 8080, 8081, 8088, 8090, 8123, 8181, 8880, 8888, 9000, 9090, 10000, 32400, 49000 };
    public static readonly HashSet<int> HttpsPorts = new() { 443, 5001, 4443, 7443, 8443, 9443 };
    public static readonly HashSet<int> BannerPorts = new() { 21, 22, 23, 25, 110, 143, 587, 3306, 5900, 6379 };

    public static string Label(int p) => Names.GetValueOrDefault(p, "Unbekannt");

    /// <summary>Baut eine TCP-Verbindung mit Zeitlimit auf. Der Versuch wird bei Zeitüberschreitung
    /// sauber abgebrochen (keine zurückgelassenen, später fehlschlagenden Tasks).</summary>
    public static async Task<TcpClient?> ConnectAsync(string ip, int port, int timeoutMs, CancellationToken ct = default)
    {
        var client = new TcpClient(AddressFamily.InterNetwork);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeoutMs);
        try
        {
            await client.ConnectAsync(IPAddress.Parse(ip), port, cts.Token).ConfigureAwait(false);
            if (client.Connected) return client;
        }
        catch (OperationCanceledException) { }
        catch (SocketException) { }
        catch (ObjectDisposedException) { }
        client.Dispose();
        return null;
    }

    /// <summary>Paralleler TCP-Connect-Scan eines Hosts.</summary>
    public static async Task<List<int>> ScanAsync(string ip, IReadOnlyList<int> ports, int timeoutMs = 800, int concurrency = 400, CancellationToken ct = default)
    {
        var open = new System.Collections.Concurrent.ConcurrentBag<int>();
        using var gate = new SemaphoreSlim(concurrency);
        var tasks = new List<Task>(ports.Count);
        foreach (var port in ports)
        {
            if (ct.IsCancellationRequested) break;
            try { await gate.WaitAsync(ct).ConfigureAwait(false); } catch (OperationCanceledException) { break; }
            tasks.Add(Task.Run(async () =>
            {
                try
                {
                    using var client = await ConnectAsync(ip, port, timeoutMs, ct).ConfigureAwait(false);
                    if (client != null) open.Add(port);
                }
                finally { gate.Release(); }
            }));
        }
        await Task.WhenAll(tasks).ConfigureAwait(false);
        return open.OrderBy(x => x).ToList();
    }

    /// <summary>Liest die Begrüßung eines Dienstes (z. B. "SSH-2.0-OpenSSH_9.6").</summary>
    public static async Task<string?> BannerAsync(string ip, int port, int timeoutMs = 1200, CancellationToken ct = default)
    {
        try
        {
            using var client = await ConnectAsync(ip, port, timeoutMs, ct).ConfigureAwait(false);
            if (client is null) return null;
            using var stream = client.GetStream();
            stream.ReadTimeout = timeoutMs;
            var buffer = new byte[2048];
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeoutMs);
            int n;
            try { n = await stream.ReadAsync(buffer, cts.Token).ConfigureAwait(false); }
            catch { return null; }
            if (n <= 0) return null;
            var text = Text.Clean(Encoding.UTF8.GetString(buffer, 0, n));
            return string.IsNullOrEmpty(text) ? null : text.Length > 200 ? text[..200] : text;
        }
        catch { return null; }
    }
}
