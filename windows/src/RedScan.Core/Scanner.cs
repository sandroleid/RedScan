using System.Text.RegularExpressions;
using RedScan.Core.Probes;

namespace RedScan.Core;

/// <summary>Steuert den gesamten Scan-Ablauf. UI-unabhängig; meldet Fortschritt über Events.
/// Events können aus Hintergrund-Threads kommen – die Oberfläche muss sie selbst auf den UI-Thread bringen.</summary>
public sealed class Scanner
{
    private readonly Dictionary<string, Device> _devices = new();
    private readonly object _lock = new();

    public NetworkInfo? Network { get; private set; }
    public bool IsScanning { get; private set; }
    public string Phase { get; private set; } = "Bereit";
    public double Progress { get; private set; }
    public string? CustomTarget { get; set; }
    public bool ArpBlocked { get; private set; }
    public double? LastDurationSeconds { get; private set; }

    public event Action? Changed;
    public event Action<Device>? DeviceUpserted;

    public IReadOnlyList<Device> SortedDevices
    {
        get { lock (_lock) return _devices.Values.OrderBy(d => d.IpSortKey).ToList(); }
    }
    public int DeviceCount { get { lock (_lock) return _devices.Count; } }
    public int TotalOpenPorts { get { lock (_lock) return _devices.Values.Sum(d => d.OpenPorts.Count); } }
    public int TotalServices { get { lock (_lock) return _devices.Values.Sum(d => d.Services.Count); } }

    public Scanner()
    {
        Network = NetworkDetector.Detect();
        Device.ComputerName = Environment.MachineName;
    }

    public NetworkInfo? RefreshNetwork() { Network = NetworkDetector.Detect(CustomTarget); return Network; }

    private void Raise() => Changed?.Invoke();
    private void SetPhase(string p) { Phase = p; Raise(); }
    private void SetProgress(double p) { Progress = p; Raise(); }

    private Device Update(string ip, string? source, Action<Device> change)
    {
        Device d;
        lock (_lock)
        {
            if (!_devices.TryGetValue(ip, out d!)) { d = new Device { Ip = ip }; _devices[ip] = d; }
            change(d);
            if (source != null) d.DiscoveredBy.Add(source);
            if (d.Mac is null)
            {
                var m = MacFromServices(d.Services);
                if (m != null) { d.Mac = m; d.DiscoveredBy.Add("MAC via Bonjour"); }
            }
            if (d.Mac != null)
            {
                d.Vendor ??= VendorDb.Shared.Lookup(d.Mac);
                d.RandomizedMac = VendorDb.IsRandomized(d.Mac);
            }
            d.Model ??= Classifier.AppleModel(d.Services);
            d.Kind = Classifier.Classify(d);
        }
        DeviceUpserted?.Invoke(d);
        return d;
    }

    private bool InScope(string ip)
    {
        var net = Network;
        if (net is null || net.Hosts.Count == 0) return false;
        var v = IPv4.ToUInt32(ip);
        var first = IPv4.ToUInt32(net.Hosts[0]);
        var last = IPv4.ToUInt32(net.Hosts[^1]);
        return v.HasValue && first.HasValue && last.HasValue && v >= first && v <= last;
    }

    public async Task RunAsync(CancellationToken ct = default)
    {
        if (IsScanning) return;
        IsScanning = true;
        var started = DateTime.UtcNow;
        try
        {
            SetProgress(0);
            SetPhase("Netzwerk wird erkannt …");
            var net = await Task.Run(() => NetworkDetector.Detect(CustomTarget), ct).ConfigureAwait(false);
            if (net is null) { SetPhase("Kein aktives Netzwerk gefunden"); return; }
            Network = net;
            lock (_lock) _devices.Clear();
            Raise();

            Update(net.Ip, "Lokal", d => { d.IsSelf = true; d.Mac = net.Mac; d.LatencyMs = 0; });

            // 0. Schon bekannte Geräte sofort anzeigen
            ApplyArp(net);

            // 1. Ping-Sweep
            var hosts = net.Hosts.Where(h => h != net.Ip).ToList();
            SetPhase($"Ping-Sweep über {hosts.Count:N0} Adressen …");
            int ticks = 0;
            await PingSweep.RunAsync(hosts,
                onReply: r => Update(r.Ip, "Ping", d =>
                {
                    d.LatencyMs = r.TimeMs;
                    if (r.Ttl > 0) d.Ttl = r.Ttl;
                    d.IsGateway = r.Ip == net.Gateway;
                }),
                onProgress: done =>
                {
                    SetProgress(0.35 * done / Math.Max(hosts.Count, 1));
                    if (Interlocked.Increment(ref ticks) % 512 == 0) ApplyArp(net);
                },
                ct: ct).ConfigureAwait(false);
            if (ct.IsCancellationRequested) return;

            // 2. ARP-Tabelle
            SetPhase("ARP-Tabelle wird ausgewertet …");
            ApplyArp(net);
            SetProgress(0.38);

            // 3. Namen & Dienste
            SetPhase("Bonjour, UPnP, NetBIOS & DNS werden abgefragt …");
            List<string> ips;
            lock (_lock) ips = _devices.Keys.ToList();

            var ssdpTask = Task.Run(() => Ssdp.Discover(3.5), ct);
            var netbiosTask = Task.Run(() => NetBios.Query(ips, 2.0), ct);
            var mdnsTask = Task.Run(() => Mdns.Browse(ips, 4.0), ct);
            var rdnsTask = ReverseDns.LookupAsync(ips, 4000, ct);

            await Task.WhenAll(ssdpTask, netbiosTask, mdnsTask, rdnsTask).ConfigureAwait(false);
            if (ct.IsCancellationRequested) return;

            var mdns = mdnsTask.Result;
            foreach (var (ip, svc) in mdns.Services)
                if (InScope(ip) || ip == net.Ip)
                    Update(ip, "Bonjour", d =>
                    {
                        if (!d.Services.Any(s => s.Id == svc.Id)) d.Services.Add(svc);
                        if (d.MdnsName is null && svc.HostName != null) d.MdnsName = svc.HostName.Trim('.');
                    });
            foreach (var (ip, name) in mdns.Hostnames)
            {
                bool known; lock (_lock) known = _devices.ContainsKey(ip);
                if (known) Update(ip, "mDNS", d => d.MdnsName ??= name.Trim('.'));
            }
            foreach (var (ip, r) in netbiosTask.Result)
                Update(ip, "NetBIOS", d => { d.NetbiosName = r.Name; d.NetbiosGroup = r.Group; d.Mac ??= r.Mac; });
            foreach (var (ip, name) in rdnsTask.Result)
            {
                bool known; lock (_lock) known = _devices.ContainsKey(ip);
                if (known) Update(ip, "DNS", d => d.Hostname = name);
            }
            SetProgress(0.5);

            // UPnP-Beschreibungen
            SetPhase("UPnP-Gerätebeschreibungen werden geladen …");
            var seen = new HashSet<string>();
            var describeTasks = new List<Task>();
            foreach (var resp in ssdpTask.Result)
            {
                if (!(InScope(resp.Ip) || resp.Ip == net.Ip)) continue;
                if (!resp.Headers.TryGetValue("LOCATION", out var loc) || !seen.Add(loc)) continue;
                var server = resp.Headers.GetValueOrDefault("SERVER");
                var ip = resp.Ip;
                describeTasks.Add(Task.Run(async () =>
                {
                    var info = await Ssdp.DescribeAsync(loc, server).ConfigureAwait(false);
                    Update(ip, "UPnP", d => { if (!d.Upnp.Any(u => u.Location == info.Location)) d.Upnp.Add(info); });
                }, ct));
            }
            await Task.WhenAll(describeTasks).ConfigureAwait(false);
            ApplyArp(net);
            SetProgress(0.55);
            if (ct.IsCancellationRequested) return;

            // 4. Port-Scan
            List<string> targets = SortedDevices.Select(d => d.Ip).ToList();
            SetPhase($"Port-Scan ({Ports.Common.Count} Ports pro Gerät) …");
            int scanned = 0;
            using (var gate = new SemaphoreSlim(16))
            {
                var portTasks = targets.Select(async ip =>
                {
                    await gate.WaitAsync(ct).ConfigureAwait(false);
                    try
                    {
                        var open = await Ports.ScanAsync(ip, Ports.Common, ct: ct).ConfigureAwait(false);
                        Update(ip, null, d =>
                        {
                            d.OpenPorts = open.Select(p => new OpenPort { Port = p, Service = Ports.Label(p) }).ToList();
                            d.PortsScanned = true;
                        });
                    }
                    finally
                    {
                        gate.Release();
                        int s = Interlocked.Increment(ref scanned);
                        SetProgress(0.55 + 0.25 * s / Math.Max(targets.Count, 1));
                    }
                });
                await Task.WhenAll(portTasks).ConfigureAwait(false);
            }
            if (ct.IsCancellationRequested) return;

            // 5. Banner & Web
            SetPhase("Banner, Webseiten & Zertifikate werden gelesen …");
            await EnrichAsync(targets, ct).ConfigureAwait(false);
            SetProgress(1);

            LastDurationSeconds = (DateTime.UtcNow - started).TotalSeconds;
            SetPhase($"Fertig – {DeviceCount} Geräte gefunden");
        }
        finally
        {
            IsScanning = false;
            Raise();
        }
    }

    private void ApplyArp(NetworkInfo net)
    {
        List<ArpTable.Entry> entries;
        try { entries = ArpTable.Read(); } catch { entries = new(); }
        ArpBlocked = entries.Count == 0;
        foreach (var e in entries)
            if (InScope(e.Ip) || e.Ip == net.Ip)
                Update(e.Ip, "ARP", d => { d.Mac = e.Mac; d.IsGateway = e.Ip == net.Gateway; });
    }

    private async Task EnrichAsync(IReadOnlyList<string> ips, CancellationToken ct)
    {
        var tasks = new List<Task>();
        using var gate = new SemaphoreSlim(64);
        foreach (var ip in ips)
        {
            List<int> ports;
            lock (_lock) ports = _devices.TryGetValue(ip, out var dd) ? dd.OpenPorts.Select(p => p.Port).ToList() : new();
            foreach (var p in ports)
            {
                var ipc = ip; var pc = p;
                tasks.Add(Task.Run(async () =>
                {
                    await gate.WaitAsync(ct).ConfigureAwait(false);
                    try
                    {
                        if (Ports.HttpsPorts.Contains(pc) || Ports.HttpPorts.Contains(pc))
                        {
                            bool tls = Ports.HttpsPorts.Contains(pc);
                            var http = await Web.FetchAsync(ipc, pc, tls, ct: ct).ConfigureAwait(false);
                            if (http != null) Update(ipc, null, d =>
                            {
                                d.Http.RemoveAll(h => h.Port == pc);
                                d.Http.Add(http);
                                d.Http.Sort((a, b) => a.Port.CompareTo(b.Port));
                                var idx = d.OpenPorts.FindIndex(o => o.Port == pc);
                                if (idx >= 0)
                                    d.OpenPorts[idx].Banner = string.Join(" · ",
                                        new[] { http.Server, http.Title != null ? $"„{http.Title}“" : null }
                                        .Where(x => !string.IsNullOrEmpty(x))).NilIfEmpty();
                            });
                        }
                        else if (Ports.BannerPorts.Contains(pc) || !Ports.Names.ContainsKey(pc))
                        {
                            var b = await Ports.BannerAsync(ipc, pc, ct: ct).ConfigureAwait(false);
                            if (b != null) Update(ipc, null, d =>
                            {
                                var idx = d.OpenPorts.FindIndex(o => o.Port == pc);
                                if (idx >= 0) d.OpenPorts[idx].Banner = b;
                            });
                        }
                    }
                    finally { gate.Release(); }
                }, ct));
            }
        }
        try { await Task.WhenAll(tasks).ConfigureAwait(false); } catch { }
    }

    // Einzelgerät
    public async Task DeepScanAsync(string ip, CancellationToken ct = default)
    {
        var open = await Ports.ScanAsync(ip, Ports.Deep, 1000, ct: ct).ConfigureAwait(false);
        Update(ip, null, d =>
        {
            d.OpenPorts = open.Select(p => d.OpenPorts.FirstOrDefault(o => o.Port == p) ?? new OpenPort { Port = p, Service = Ports.Label(p) }).ToList();
            d.PortsScanned = true;
            d.DeepScanned = true;
        });
        await EnrichAsync(new[] { ip }, ct).ConfigureAwait(false);
    }

    public Device? Get(string ip) { lock (_lock) return _devices.GetValueOrDefault(ip); }

    /// <summary>Ersatz, wenn ARP fehlt: AirPlay deviceid oder RAOP-Name "AABBCCDDEEFF@Name".</summary>
    public static string? MacFromServices(List<BonjourService> services)
    {
        foreach (var s in services)
        {
            if (s.Txt.TryGetValue("deviceid", out var id) && Regex.IsMatch(id, @"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"))
                return id.ToUpperInvariant();
            if (s.Type.StartsWith("_raop"))
            {
                var m = Regex.Match(s.Name, @"^([0-9A-Fa-f]{12})@");
                if (m.Success)
                {
                    var hex = m.Groups[1].Value;
                    return string.Join(":", Enumerable.Range(0, 6).Select(i => hex.Substring(i * 2, 2))).ToUpperInvariant();
                }
            }
        }
        return null;
    }
}
