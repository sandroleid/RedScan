namespace RedScan.Core;

public enum DeviceKind
{
    ThisPc, Router, Computer, Laptop, Phone, Tablet, Tv, Speaker, Printer,
    Nas, Camera, Iot, Console, Server, Watch, Unknown
}

public static class DeviceKindInfo
{
    public static string Label(this DeviceKind k) => k switch
    {
        DeviceKind.ThisPc => "Dieser PC",
        DeviceKind.Router => "Router / AP",
        DeviceKind.Computer => "Computer",
        DeviceKind.Laptop => "Laptop",
        DeviceKind.Phone => "Smartphone",
        DeviceKind.Tablet => "Tablet",
        DeviceKind.Tv => "TV / Streaming",
        DeviceKind.Speaker => "Lautsprecher",
        DeviceKind.Printer => "Drucker",
        DeviceKind.Nas => "NAS / Speicher",
        DeviceKind.Camera => "Kamera",
        DeviceKind.Iot => "Smart Home / IoT",
        DeviceKind.Console => "Spielkonsole",
        DeviceKind.Server => "Server",
        DeviceKind.Watch => "Watch",
        _ => "Unbekannt"
    };

    /// <summary>Segoe-MDL2/Fluent-Symbol-Glyph (für die WinUI-Oberfläche).</summary>
    public static string Glyph(this DeviceKind k) => k switch
    {
        DeviceKind.ThisPc => "",      // Devices
        DeviceKind.Router => "",      // NetworkTower
        DeviceKind.Computer => "",    // Devices2
        DeviceKind.Laptop => "",
        DeviceKind.Phone => "",       // CellPhone
        DeviceKind.Tablet => "",      // Tablet
        DeviceKind.Tv => "",          // Tv
        DeviceKind.Speaker => "",     // Speakers
        DeviceKind.Printer => "",     // Print
        DeviceKind.Nas => "",         // Storage/Save
        DeviceKind.Camera => "",      // Camera
        DeviceKind.Iot => "",         // Lightbulb
        DeviceKind.Console => "",     // Game
        DeviceKind.Server => "",      // Server/Streaming
        DeviceKind.Watch => "",       // Stopwatch-ish
        _ => ""                        // Help
    };
}

public class OpenPort
{
    public int Port { get; set; }
    public string Service { get; set; } = "";
    public string? Banner { get; set; }

    public string PortText => Port.ToString();
    public bool HasBanner => !string.IsNullOrEmpty(Banner);
}

public class BonjourService
{
    public string Name { get; set; } = "";
    public string Type { get; set; } = "";
    public int Port { get; set; }
    public string? HostName { get; set; }
    public Dictionary<string, string> Txt { get; set; } = new();
    public string TypeLabel => BonjourTypes.Label(Type);
    public string Id => Type + "|" + Name;
}

public class UPnPInfo
{
    public string Location { get; set; } = "";
    public string? Server { get; set; }
    public string? FriendlyName { get; set; }
    public string? Manufacturer { get; set; }
    public string? ModelName { get; set; }
    public string? ModelNumber { get; set; }
    public string? ModelDescription { get; set; }
    public string? SerialNumber { get; set; }
    public string? DeviceType { get; set; }
    public string? PresentationUrl { get; set; }
}

public class HttpInfo
{
    public int Port { get; set; }
    public bool Tls { get; set; }
    public int? Status { get; set; }
    public string? Server { get; set; }
    public string? PoweredBy { get; set; }
    public string? Title { get; set; }
    public string? Certificate { get; set; }
}

public class Device
{
    public string Ip { get; set; } = "";
    public string? Mac { get; set; }
    public string? Vendor { get; set; }
    public bool RandomizedMac { get; set; }
    public string? Hostname { get; set; }
    public string? MdnsName { get; set; }
    public string? NetbiosName { get; set; }
    public string? NetbiosGroup { get; set; }
    public double? LatencyMs { get; set; }
    public int? Ttl { get; set; }
    public List<OpenPort> OpenPorts { get; set; } = new();
    public List<BonjourService> Services { get; set; } = new();
    public List<UPnPInfo> Upnp { get; set; } = new();
    public List<HttpInfo> Http { get; set; } = new();
    public string? Model { get; set; }
    public DeviceKind Kind { get; set; } = DeviceKind.Unknown;
    public bool IsGateway { get; set; }
    public bool IsSelf { get; set; }
    public bool PortsScanned { get; set; }
    public bool DeepScanned { get; set; }
    public HashSet<string> DiscoveredBy { get; set; } = new();
    public DateTime FirstSeen { get; set; } = DateTime.Now;

    public uint IpSortKey => IPv4.ToUInt32(Ip) ?? 0;

    public string VendorDisplay => Vendor ?? (RandomizedMac ? "Private (zufällige) MAC" : "Hersteller unbekannt");
    public string PortCountText => $"{OpenPorts.Count} Ports";
    public string LatencyText => LatencyMs is null ? "" : LatencyMs < 1 ? "<1 ms" : $"{Math.Round(LatencyMs.Value)} ms";

    public static string? ComputerName { get; set; }

    public string DisplayName
    {
        get
        {
            if (IsSelf && !string.IsNullOrEmpty(ComputerName)) return ComputerName!;
            var fn = Upnp.Select(u => u.FriendlyName).FirstOrDefault(x => !string.IsNullOrEmpty(x));
            if (!string.IsNullOrEmpty(fn)) return fn!;
            var sv = Services.FirstOrDefault(s =>
                s.Type.StartsWith("_device-info") || s.Type.StartsWith("_companion-link") ||
                s.Type.StartsWith("_airplay") || s.Type.StartsWith("_googlecast"));
            if (sv != null)
            {
                if (sv.Txt.TryGetValue("fn", out var f) && !string.IsNullOrEmpty(f)) return f;
                return sv.Name;
            }
            if (!string.IsNullOrEmpty(MdnsName)) return MdnsName!.Replace(".local", "").Trim('.');
            if (!string.IsNullOrEmpty(NetbiosName)) return NetbiosName!;
            if (Services.Count > 0) return Services[0].Txt.GetValueOrDefault("fn") ?? Services[0].Name;
            if (!string.IsNullOrEmpty(Hostname)) return Hostname!;
            if (!string.IsNullOrEmpty(Vendor)) return $"{Vendor!.Split(',', '.')[0]}-Gerät";
            return Ip;
        }
    }

    public string SearchBlob
    {
        get
        {
            var parts = new List<string?> { Ip, Mac, Vendor, Hostname, MdnsName, NetbiosName, NetbiosGroup, Model, Kind.Label() };
            parts.AddRange(Services.Select(s => $"{s.Name} {s.Type} {string.Join(' ', s.Txt.Values)}"));
            parts.AddRange(Upnp.Select(u => $"{u.FriendlyName} {u.Manufacturer} {u.ModelName} {u.ModelDescription} {u.DeviceType} {u.Server}"));
            parts.AddRange(Http.Select(h => $"{h.Server} {h.Title} {h.PoweredBy}"));
            parts.AddRange(OpenPorts.Select(p => $"{p.Port} {p.Service} {p.Banner}"));
            return string.Join(' ', parts.Where(x => !string.IsNullOrEmpty(x))).ToLowerInvariant();
        }
    }

    public string? OsGuess
    {
        get
        {
            var blob = SearchBlob;
            if (IsSelf) return "Windows (dieser PC)";
            if (Model != null)
            {
                var m = Model.ToLowerInvariant();
                if (m.StartsWith("iphone")) return "iOS";
                if (m.StartsWith("ipad")) return "iPadOS";
                if (m.StartsWith("appletv")) return "tvOS";
                if (m.StartsWith("audioaccessory")) return "HomePod-Software";
                if (m.Contains("macbook") || m.StartsWith("imac") || m.StartsWith("mac")) return "macOS";
                if (m.StartsWith("watch")) return "watchOS";
            }
            if (blob.Contains("ubuntu")) return "Linux (Ubuntu)";
            if (blob.Contains("debian")) return "Linux (Debian)";
            if (blob.Contains("raspbian") || blob.Contains("raspberry")) return "Linux (Raspberry Pi OS)";
            if (blob.Contains("openwrt")) return "Linux (OpenWrt)";
            if (blob.Contains("fritz")) return "FRITZ!OS";
            if (blob.Contains("synology") || blob.Contains("dsm")) return "Synology DSM";
            if (blob.Contains("windows") || OpenPorts.Any(p => p.Port is 135 or 3389 or 445)) return "Windows";
            if (Kind == DeviceKind.Phone && (Vendor?.ToLowerInvariant().Contains("apple") ?? false)) return "iOS";
            if (blob.Contains("android") || OpenPorts.Any(p => p.Port == 5555)) return "Android";
            if (OpenPorts.Any(p => p.Port == 62078)) return "iOS / iPadOS";
            if (Ttl is int ttl)
            {
                if (ttl > 128) return "Netzwerk-OS (Router/Switch)";
                if (ttl > 64) return $"Windows (TTL {ttl})";
                if (Vendor?.ToLowerInvariant().Contains("apple") ?? false) return "Apple (iOS/macOS)";
                return $"Linux / Unix / Android (TTL {ttl})";
            }
            return null;
        }
    }
}

public class NetworkInfo
{
    public string Interface { get; set; } = "";
    public string Ip { get; set; } = "";
    public string Netmask { get; set; } = "";
    public int Prefix { get; set; }
    public string? Mac { get; set; }
    public string? Gateway { get; set; }
    public List<string> Dns { get; set; } = new();
    public string? Ssid { get; set; }
    public string Cidr { get; set; } = "";
    public List<string> Hosts { get; set; } = new();
    public string? Note { get; set; }
}
