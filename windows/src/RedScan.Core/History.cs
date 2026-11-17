using System.Text.Json;
using System.Text.Json.Serialization;

namespace RedScan.Core;

public class KnownDevice
{
    public string Key { get; set; } = "";
    public string? Mac { get; set; }
    public string LastIp { get; set; } = "";
    public List<string> Ips { get; set; } = new();
    public string Name { get; set; } = "";
    public DeviceKind Kind { get; set; }
    public string? Vendor { get; set; }
    public string Network { get; set; } = "";
    public List<int> OpenPorts { get; set; } = new();
    public DateTime FirstSeen { get; set; }
    public DateTime LastSeen { get; set; }
    public int SeenCount { get; set; }

    [JsonIgnore] public string SubText => string.Join(" · ", new[] { Kind.Label(), Vendor }.Where(x => !string.IsNullOrEmpty(x)));
    [JsonIgnore] public string StatusText => $"zuletzt {LastSeen:dd.MM.yyyy HH:mm} · {SeenCount}× gesehen";
    [JsonIgnore] public string MacDisplay => Mac ?? "keine MAC";
    [JsonIgnore] public bool HasMac => !string.IsNullOrEmpty(Mac);
}

public class ScanRecord
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime Date { get; set; }
    public string Network { get; set; } = "";
    public string? Ssid { get; set; }
    public double? Duration { get; set; }
    public List<string> DeviceKeys { get; set; } = new();
    public List<string> NewKeys { get; set; } = new();
    public List<string> GoneKeys { get; set; } = new();

    [JsonIgnore] public string Title => Date.ToString("dd.MM.yyyy HH:mm");
    [JsonIgnore] public string Sub => string.Join(" · ", new[] { Ssid, Network, DeviceKeys.Count + " Geräte", Duration is { } d ? $"{d:F0} s" : null }
        .Where(x => !string.IsNullOrEmpty(x)));
    [JsonIgnore] public string ChangesText
    {
        get
        {
            var parts = new List<string>();
            if (NewKeys.Count > 0) parts.Add($"+{NewKeys.Count} neu");
            if (GoneKeys.Count > 0) parts.Add($"−{GoneKeys.Count} weg");
            return string.Join("   ", parts);
        }
    }
    [JsonIgnore] public bool HasChanges => NewKeys.Count > 0 || GoneKeys.Count > 0;
}

public sealed class HistoryStore
{
    public Dictionary<string, KnownDevice> Known { get; private set; } = new();
    public List<ScanRecord> Scans { get; private set; } = new();
    public HashSet<string> NewInLastScan { get; private set; } = new();

    private class FileModel { public Dictionary<string, KnownDevice> Known { get; set; } = new(); public List<ScanRecord> Scans { get; set; } = new(); }

    private readonly string _path;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public HistoryStore(string? path = null)
    {
        var dir = path != null ? Path.GetDirectoryName(path)!
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RedScan");
        Directory.CreateDirectory(dir);
        _path = path ?? Path.Combine(dir, "history.json");
        Load();
    }

    public static string KeyFor(Device d) => d.Mac ?? $"ip:{d.Ip}";

    public IReadOnlyList<KnownDevice> SortedKnown => Known.Values.OrderByDescending(k => k.LastSeen).ToList();
    public KnownDevice? KnownFor(Device d) => Known.GetValueOrDefault(KeyFor(d));

    public void Record(IReadOnlyList<Device> devices, NetworkInfo network, double? duration)
    {
        var now = DateTime.Now;
        var keys = new List<string>();
        var newKeys = new List<string>();

        foreach (var d in devices)
        {
            var k = KeyFor(d);
            keys.Add(k);

            // War früher nur per IP bekannt, jetzt mit MAC → alten Eintrag übernehmen
            if (d.Mac != null && !Known.ContainsKey(k) && Known.TryGetValue($"ip:{d.Ip}", out var old))
            {
                Known.Remove($"ip:{d.Ip}");
                old.Key = k; old.Mac = d.Mac;
                Known[k] = old;
                foreach (var s in Scans)
                {
                    s.DeviceKeys = s.DeviceKeys.Select(x => x == $"ip:{d.Ip}" ? k : x).ToList();
                    s.NewKeys = s.NewKeys.Select(x => x == $"ip:{d.Ip}" ? k : x).ToList();
                    s.GoneKeys = s.GoneKeys.Select(x => x == $"ip:{d.Ip}" ? k : x).ToList();
                }
            }

            if (Known.TryGetValue(k, out var kd))
            {
                kd.LastIp = d.Ip;
                if (!kd.Ips.Contains(d.Ip)) kd.Ips.Add(d.Ip);
                kd.Name = d.DisplayName; kd.Kind = d.Kind;
                kd.Vendor = d.Vendor ?? kd.Vendor;
                kd.Mac = d.Mac ?? kd.Mac;
                kd.Network = network.Cidr;
                kd.OpenPorts = d.OpenPorts.Select(p => p.Port).ToList();
                kd.LastSeen = now;
                kd.SeenCount++;
            }
            else
            {
                newKeys.Add(k);
                Known[k] = new KnownDevice
                {
                    Key = k, Mac = d.Mac, LastIp = d.Ip, Ips = new() { d.Ip },
                    Name = d.DisplayName, Kind = d.Kind, Vendor = d.Vendor, Network = network.Cidr,
                    OpenPorts = d.OpenPorts.Select(p => p.Port).ToList(),
                    FirstSeen = now, LastSeen = now, SeenCount = 1
                };
            }
        }

        var previous = Scans.FirstOrDefault(s => s.Network == network.Cidr);
        var gone = previous != null ? previous.DeviceKeys.Except(keys).OrderBy(x => x).ToList() : new List<string>();
        bool firstScanOfNetwork = previous is null;
        NewInLastScan = firstScanOfNetwork ? new() : newKeys.ToHashSet();

        Scans.Insert(0, new ScanRecord
        {
            Date = now, Network = network.Cidr, Ssid = network.Ssid, Duration = duration,
            DeviceKeys = keys, NewKeys = firstScanOfNetwork ? new() : newKeys, GoneKeys = gone
        });
        if (Scans.Count > 200) Scans.RemoveRange(200, Scans.Count - 200);
        Save();
    }

    public void Remove(string key) { Known.Remove(key); NewInLastScan.Remove(key); Save(); }
    public void Clear() { Known.Clear(); Scans.Clear(); NewInLastScan.Clear(); Save(); }

    private void Load()
    {
        try
        {
            if (!File.Exists(_path)) return;
            var model = JsonSerializer.Deserialize<FileModel>(File.ReadAllText(_path), JsonOpts);
            if (model != null) { Known = model.Known; Scans = model.Scans; }
        }
        catch { }
    }

    private void Save()
    {
        try { File.WriteAllText(_path, JsonSerializer.Serialize(new FileModel { Known = Known, Scans = Scans }, JsonOpts)); }
        catch { }
    }
}
