using Microsoft.UI.Xaml;
using RedScan.Core;

namespace RedScan.App;

/// <summary>Formatierungs-Hilfen für die x:Bind-Funktionsbindungen in XAML.</summary>
public static class Fmt
{
    public static string Glyph(DeviceKind k) => k.Glyph();
    public static string KindLabel(DeviceKind k) => k.Label();

    public static Visibility Vis(bool b) => b ? Visibility.Visible : Visibility.Collapsed;
    public static Visibility VisNot(bool b) => b ? Visibility.Collapsed : Visibility.Visible;
    public static Visibility VisIfText(string? s) => string.IsNullOrEmpty(s) ? Visibility.Collapsed : Visibility.Visible;

    public static string Vendor(Device d) =>
        d.Vendor ?? (d.RandomizedMac ? "Private (zufällige) MAC" : "Hersteller unbekannt");

    public static string Ports(Device d) => d.OpenPorts.Count == 0 ? "–" : string.Join(" ", d.OpenPorts.Select(p => p.Port));
    public static int PortCount(Device d) => d.OpenPorts.Count;
    public static int ServiceCount(Device d) => d.Services.Count;

    public static string Latency(Device d) =>
        d.LatencyMs is null ? "" : d.LatencyMs < 1 ? "<1 ms" : $"{Math.Round(d.LatencyMs.Value)} ms";

    public static string PortLabel(OpenPort p) => p.Service;
    public static string PortText(OpenPort p) => p.Port.ToString();
    public static Visibility BannerVis(OpenPort p) => VisIfText(p.Banner);

    public static string ServiceTitle(BonjourService s) => s.TypeLabel;
    public static string HttpUrl(HttpInfo h) => $"{(h.Tls ? "https" : "http")}://:{h.Port}";

    public static string KnownStatus(KnownDevice k) =>
        $"zuletzt {k.LastSeen:dd.MM.yyyy HH:mm} · {k.SeenCount}× gesehen";
    public static string KnownSub(KnownDevice k) =>
        string.Join(" · ", new[] { k.Kind.Label(), k.Vendor }.Where(x => !string.IsNullOrEmpty(x)));
    public static string KnownMac(KnownDevice k) => k.Mac ?? "keine MAC";
    public static bool HasMac(KnownDevice k) => !string.IsNullOrEmpty(k.Mac);
    public static Visibility MacVis(KnownDevice k) => Vis(!string.IsNullOrEmpty(k.Mac));

    public static string ScanTitle(ScanRecord s) => s.Date.ToString("dd.MM.yyyy HH:mm");
    public static string ScanSub(ScanRecord s) =>
        string.Join(" · ", new[] { s.Ssid, s.Network, s.DeviceKeys.Count + " Geräte", s.Duration is { } d ? $"{d:F0} s" : null }
            .Where(x => !string.IsNullOrEmpty(x)));
    public static string ScanChanges(ScanRecord s)
    {
        var parts = new List<string>();
        if (s.NewKeys.Count > 0) parts.Add($"+{s.NewKeys.Count} neu");
        if (s.GoneKeys.Count > 0) parts.Add($"−{s.GoneKeys.Count} weg");
        return string.Join("  ", parts);
    }
    public static Visibility ScanChangesVis(ScanRecord s) => Vis(s.NewKeys.Count > 0 || s.GoneKeys.Count > 0);
}
