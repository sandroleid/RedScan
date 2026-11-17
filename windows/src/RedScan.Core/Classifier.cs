namespace RedScan.Core;

/// <summary>Heuristik: Aus Hersteller, Namen, Diensten und Ports den Gerätetyp ableiten.</summary>
public static class Classifier
{
    public static DeviceKind Classify(Device d)
    {
        if (d.IsSelf) return DeviceKind.ThisPc;
        if (d.IsGateway) return DeviceKind.Router;

        var v = (d.Vendor ?? "").ToLowerInvariant();
        var model = (d.Model ?? "").ToLowerInvariant();
        var names = string.Join(' ', new[] { d.MdnsName, d.Hostname, d.NetbiosName }
            .Concat(d.Services.Select(s => s.Name))
            .Concat(d.Upnp.SelectMany(u => new[] { u.FriendlyName, u.ModelName, u.ModelDescription }))
            .Where(x => !string.IsNullOrEmpty(x))).ToLowerInvariant();
        var types = d.Services.Select(s => s.Type.ToLowerInvariant()).ToHashSet();
        var ports = d.OpenPorts.Select(p => p.Port).ToHashSet();
        var upnp = string.Join(' ', d.Upnp.Select(u => u.DeviceType).Where(x => x != null)).ToLowerInvariant();

        bool Has(string t) => types.Any(x => x.StartsWith(t));
        bool VendorIs(params string[] list) => list.Any(x => v.Contains(x));
        bool NameHas(params string[] list) => list.Any(x => names.Contains(x));

        if (!string.IsNullOrEmpty(model))
        {
            if (model.StartsWith("iphone")) return DeviceKind.Phone;
            if (model.StartsWith("ipad")) return DeviceKind.Tablet;
            if (model.StartsWith("watch")) return DeviceKind.Watch;
            if (model.StartsWith("appletv")) return DeviceKind.Tv;
            if (model.StartsWith("audioaccessory")) return DeviceKind.Speaker;
            if (model.Contains("macbook")) return DeviceKind.Laptop;
            if (model.StartsWith("imac") || model.StartsWith("macmini") || model.StartsWith("macpro") || model.StartsWith("mac")) return DeviceKind.Computer;
        }

        if (NameHas("iphone", "galaxy-s", "pixel", "android", "redmi", "oneplus", "smartphone")) return DeviceKind.Phone;
        if (NameHas("ipad", "galaxy-tab", "tablet")) return DeviceKind.Tablet;
        if (NameHas("macbook", "laptop-", "thinkpad", "notebook")) return DeviceKind.Laptop;
        if (NameHas("playstation", "ps4", "ps5", "xbox", "nintendo", "switch")) return DeviceKind.Console;
        if (NameHas("fritz!box", "fritzbox", "speedport", "router", "repeater", "access point", "unifi")) return DeviceKind.Router;
        if (NameHas("desktop-", "-pc")) return DeviceKind.Computer;

        if (Has("_ipp") || Has("_printer") || Has("_pdl-datastream") || Has("_uscan") || ports.Contains(9100) || ports.Contains(631) || ports.Contains(515)
            || VendorIs("hewlett", "hp inc", "brother", "canon", "seiko epson", "epson", "xerox", "kyocera", "lexmark", "ricoh")) return DeviceKind.Printer;
        if (VendorIs("sonos") || Has("_sonos") || ports.Contains(1400)) return DeviceKind.Speaker;
        if (Has("_googlecast") || Has("_amzn-wplay") || Has("_androidtvremote") || Has("_appletv") || ports.Contains(8008) || ports.Contains(8060)
            || (upnp.Contains("mediarenderer") && VendorIs("samsung", "lg ", "sony", "philips", "tcl", "hisense", "panasonic", "vizio"))
            || VendorIs("roku")) return DeviceKind.Tv;
        if (VendorIs("synology", "qnap", "western digital", "buffalo", "asustor") || (ports.Contains(5000) && ports.Contains(5001)) || Has("_adisk")) return DeviceKind.Nas;
        if (VendorIs("hikvision", "dahua", "axis comm", "reolink", "arlo", "wyze", "ezviz", "foscam", "amcrest") || (ports.Contains(554) && !ports.Contains(7000))) return DeviceKind.Camera;
        if (VendorIs("nintendo", "sony interactive")) return DeviceKind.Console;
        if (Has("_hap") || Has("_homekit") || Has("_hue") || Has("_esphomelib") || Has("_matter") || Has("_shelly") || ports.Contains(1883) || ports.Contains(6668) || ports.Contains(8123)
            || VendorIs("espressif", "tuya", "shelly", "signify", "philips lighting", "xiaomi", "lumi", "tasmota", "ring ", "nest", "ecobee", "tado", "ikea", "lifx", "sonoff")) return DeviceKind.Iot;
        if (VendorIs("amazon")) return DeviceKind.Speaker;
        if (ports.Contains(62078) || Has("_apple-mobdev")) return DeviceKind.Phone;
        if (VendorIs("avm", "tp-link", "netgear", "ubiquiti", "cisco", "linksys", "zyxel", "mikrotik", "juniper", "aruba", "d-link", "draytek", "lancom", "sagemcom", "arcadyan", "technicolor")
            || ports.Contains(8291) || ports.Contains(49000)) return DeviceKind.Router;
        if (VendorIs("raspberry")) return DeviceKind.Server;
        if (ports.Contains(3389) || ports.Contains(135) || ports.Contains(5357) || d.NetbiosName != null) return DeviceKind.Computer;
        if (Has("_afpovertcp") || Has("_rfb") || ports.Contains(548) || ports.Contains(5900)) return DeviceKind.Computer;
        if (ports.Contains(22) && (ports.Contains(80) || ports.Contains(443) || ports.Contains(3306) || ports.Contains(5432))) return DeviceKind.Server;
        if (VendorIs("samsung", "lg electronics", "oppo", "vivo", "huawei", "honor", "motorola", "oneplus", "realme", "google") && ports.Count == 0) return DeviceKind.Phone;
        if (VendorIs("intel", "dell", "lenovo", "asustek", "micro-star", "gigabyte", "liteon", "azurewave", "realtek")) return DeviceKind.Computer;
        if (Has("_companion-link")) return DeviceKind.Computer;
        if (d.RandomizedMac && ports.Count == 0) return DeviceKind.Phone;
        return DeviceKind.Unknown;
    }

    public static string? AppleModel(List<BonjourService> services)
    {
        foreach (var s in services)
            foreach (var key in new[] { "model", "am", "md" })
                if (s.Txt.TryGetValue(key, out var m) && !string.IsNullOrEmpty(m) && m.Length < 60) return m;
        return null;
    }

    public static string PrettyModel(string m)
    {
        var l = m.ToLowerInvariant();
        var map = new (string, string)[]
        {
            ("macbookpro", "MacBook Pro"), ("macbookair", "MacBook Air"), ("macbook", "MacBook"), ("imac", "iMac"),
            ("macmini", "Mac mini"), ("macpro", "Mac Pro"), ("iphone", "iPhone"), ("ipad", "iPad"),
            ("appletv", "Apple TV"), ("audioaccessory", "HomePod"), ("watch", "Apple Watch"),
        };
        foreach (var (k, val) in map) if (l.StartsWith(k)) return $"{val} ({m})";
        return m;
    }
}
