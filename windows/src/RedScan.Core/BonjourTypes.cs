namespace RedScan.Core;

public static class BonjourTypes
{
    public static readonly Dictionary<string, string> Known = new()
    {
        ["_airplay._tcp."] = "AirPlay",
        ["_raop._tcp."] = "AirPlay-Audio",
        ["_companion-link._tcp."] = "Apple Companion",
        ["_device-info._tcp."] = "Geräteinfo",
        ["_homekit._tcp."] = "HomeKit",
        ["_hap._tcp."] = "HomeKit-Zubehör",
        ["_sleep-proxy._udp."] = "Bonjour Sleep Proxy",
        ["_apple-mobdev2._tcp."] = "Apple Mobilgerät",
        ["_appletv-v2._tcp."] = "Apple TV",
        ["_afpovertcp._tcp."] = "AFP-Freigabe",
        ["_smb._tcp."] = "SMB-Freigabe",
        ["_adisk._tcp."] = "Time Machine",
        ["_nfs._tcp."] = "NFS",
        ["_ssh._tcp."] = "SSH",
        ["_sftp-ssh._tcp."] = "SFTP",
        ["_rfb._tcp."] = "Bildschirmfreigabe (VNC)",
        ["_workstation._tcp."] = "Workstation",
        ["_http._tcp."] = "Webserver",
        ["_https._tcp."] = "Webserver (TLS)",
        ["_ipp._tcp."] = "Drucker (IPP)",
        ["_ipps._tcp."] = "Drucker (IPPS)",
        ["_printer._tcp."] = "Drucker (LPD)",
        ["_pdl-datastream._tcp."] = "Drucker (RAW)",
        ["_scanner._tcp."] = "Scanner",
        ["_uscan._tcp."] = "Scanner (eSCL)",
        ["_googlecast._tcp."] = "Google Cast",
        ["_spotify-connect._tcp."] = "Spotify Connect",
        ["_sonos._tcp."] = "Sonos",
        ["_amzn-wplay._tcp."] = "Amazon Fire TV",
        ["_androidtvremote2._tcp."] = "Android TV",
        ["_hue._tcp."] = "Philips Hue",
        ["_home-assistant._tcp."] = "Home Assistant",
        ["_esphomelib._tcp."] = "ESPHome",
        ["_matter._tcp."] = "Matter",
        ["_matterc._udp."] = "Matter (Inbetriebnahme)",
        ["_meshcop._udp."] = "Thread Border Router",
        ["_mqtt._tcp."] = "MQTT",
        ["_daap._tcp."] = "iTunes-Mediathek",
        ["_plexmediasvr._tcp."] = "Plex",
        ["_teamviewer._tcp."] = "TeamViewer",
        ["_rdp._tcp."] = "Remotedesktop",
        ["_shelly._tcp."] = "Shelly",
    };

    public static string Label(string type)
    {
        var t = type.EndsWith(".") ? type : type + ".";
        if (Known.TryGetValue(t, out var v)) return v;
        return type.Replace("._tcp.", "").Replace("._udp.", "").Replace("_", "");
    }
}
