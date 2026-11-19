using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.UI.Dispatching;
using RedScan.Core;

namespace RedScan.App;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly Scanner _scanner = new();
    private readonly HistoryStore _history = new();
    private readonly DispatcherQueue _dispatcher = DispatcherQueue.GetForCurrentThread();
    private readonly DispatcherQueueTimer _timer;
    private CancellationTokenSource? _cts;

    public ObservableCollection<Device> Devices { get; } = new();
    public ObservableCollection<KnownDevice> KnownDevices { get; } = new();
    public ObservableCollection<ScanRecord> Scans { get; } = new();
    public ObservableCollection<OpenPort> SelectedPorts { get; } = new();
    public ObservableCollection<BonjourService> SelectedServices { get; } = new();
    public ObservableCollection<HttpInfo> SelectedHttp { get; } = new();
    public ObservableCollection<UPnPInfo> SelectedUpnp { get; } = new();

    public RelayCommand ScanCommand { get; }
    public RelayCommand DeepScanCommand { get; }
    public RelayCommand WakeCommand { get; }
    public RelayCommand WakeKnownCommand { get; }
    public RelayCommand ExportJsonCommand { get; }
    public RelayCommand ExportCsvCommand { get; }
    public RelayCommand ShowDevicesCommand { get; }
    public RelayCommand ShowHistoryCommand { get; }
    public RelayCommand ClearHistoryCommand { get; }
    public RelayCommand RefreshNetworkCommand { get; }

    public event Action<string>? Toast;

    public MainViewModel()
    {
        _timer = _dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(350);
        _timer.Tick += (_, _) => Refresh();

        ScanCommand = new RelayCommand(() => { if (_scanner.IsScanning) Cancel(); else _ = StartAsync(); });
        DeepScanCommand = new RelayCommand(async () =>
        {
            if (SelectedDevice is { } d) { await _scanner.DeepScanAsync(d.Ip); Refresh(); }
        });
        WakeCommand = new RelayCommand(() => WakeDevice(SelectedDevice?.Mac, SelectedDevice?.DisplayName));
        WakeKnownCommand = new RelayCommand(p => { if (p is KnownDevice k) WakeDevice(k.Mac, k.Name); });
        ExportJsonCommand = new RelayCommand(ExportJson);
        ExportCsvCommand = new RelayCommand(ExportCsv);
        ShowDevicesCommand = new RelayCommand(() => ShowHistory = false);
        ShowHistoryCommand = new RelayCommand(() => ShowHistory = true);
        ClearHistoryCommand = new RelayCommand(() => { _history.Clear(); RefreshHistory(); });
        RefreshNetworkCommand = new RelayCommand(() => { _scanner.RefreshNetwork(); RaiseNetwork(); });

        RefreshHistory();
        RaiseNetwork();
    }

    // MARK: Scan-Steuerung

    public async Task StartAsync()
    {
        if (_scanner.IsScanning) return;
        _cts = new CancellationTokenSource();
        _timer.Start();
        OnPropertyChanged(nameof(IsScanning));
        OnPropertyChanged(nameof(ScanButtonText));
        ScanCommand.RaiseCanExecuteChanged();
        try { await _scanner.RunAsync(_cts.Token); }
        catch { }
        finally
        {
            _timer.Stop();
            if (_scanner.Network is { } net && _scanner.DeviceCount > 0)
                _history.Record(_scanner.SortedDevices, net, _scanner.LastDurationSeconds);
            Refresh();
            RefreshHistory();
            OnPropertyChanged(nameof(IsScanning));
            OnPropertyChanged(nameof(ScanButtonText));
        }
    }

    public void Cancel() => _cts?.Cancel();

    public string? CustomTarget
    {
        get => _scanner.CustomTarget;
        set { _scanner.CustomTarget = value; _scanner.RefreshNetwork(); RaiseNetwork(); }
    }

    // MARK: Anzeige aktualisieren

    private void Refresh()
    {
        var snapshot = _scanner.SortedDevices;
        var filtered = ApplyFilter(snapshot);

        // Devices-Collection nur abgleichen statt neu aufbauen: Ein Clear() + Neu-Einfügen alle 350 ms
        // ließ sämtliche Karten während des Scans flackern.
        SyncDevices(filtered);

        if (SelectedDevice != null)
        {
            var still = snapshot.FirstOrDefault(d => d.Ip == SelectedDevice.Ip);
            if (still != null)
            {
                if (!ReferenceEquals(still, SelectedDevice)) SelectedDevice = still;
                else if (DetailState(still) != _detailState) RebuildSelectedDetails();
            }
        }

        Phase = _scanner.Phase;
        Progress = _scanner.Progress;
        OnPropertyChanged(nameof(DeviceCount));
        OnPropertyChanged(nameof(TotalOpenPorts));
        OnPropertyChanged(nameof(TotalServices));
        OnPropertyChanged(nameof(ArpBlocked));
        OnPropertyChanged(nameof(Subtitle));
    }

    // Zuletzt angezeigter Zustand je Karte bzw. der Detailansicht – nur bei Änderung wird neu gezeichnet.
    private readonly Dictionary<Device, string> _cardState = new(ReferenceEqualityComparer.Instance);
    private string _detailState = "";

    private void SyncDevices(IReadOnlyList<Device> target)
    {
        var wanted = new HashSet<Device>(target, ReferenceEqualityComparer.Instance);
        for (int i = Devices.Count - 1; i >= 0; i--)
            if (!wanted.Contains(Devices[i])) Devices.RemoveAt(i);

        for (int i = 0; i < target.Count; i++)
        {
            var d = target[i];
            if (i < Devices.Count && ReferenceEquals(Devices[i], d)) continue;
            int at = -1;
            for (int j = i + 1; j < Devices.Count; j++)
                if (ReferenceEquals(Devices[j], d)) { at = j; break; }
            if (at >= 0) Devices.Move(at, i); else Devices.Insert(i, d);
        }

        foreach (var stale in _cardState.Keys.Where(k => !wanted.Contains(k)).ToList()) _cardState.Remove(stale);
        foreach (var d in target)
        {
            var state = CardState(d);
            if (_cardState.TryGetValue(d, out var old))
            {
                if (old == state) continue;
                _cardState[d] = state;
                d.NotifyChanged();   // nur diese eine Karte aktualisiert ihre Texte
            }
            else _cardState[d] = state;
        }
    }

    private static string CardState(Device d) =>
        string.Join("|", d.Kind, d.IsGateway, d.DisplayName, d.VendorDisplay, d.PortCountText, d.LatencyText,
            d.Mac, d.Vendor, d.Hostname, d.MdnsName, d.NetbiosName);

    private static string DetailState(Device d) =>
        string.Join("|", CardState(d), d.OsGuess, d.DeepScanned,
            string.Join(",", d.OpenPorts.Select(p => $"{p.Port}:{p.Service}:{p.Banner}")),
            string.Join(",", d.Services.Select(s => $"{s.Name}:{s.Type}")),
            string.Join(",", d.Http.Select(h => $"{h.Server}:{h.Title}")),
            string.Join(",", d.Upnp.Select(u => u.FriendlyName)));

    private IReadOnlyList<Device> ApplyFilter(IReadOnlyList<Device> list)
    {
        IEnumerable<Device> q = list;
        if (KindFilter is { } k) q = q.Where(d => d.Kind == k);
        var s = (SearchText ?? "").Trim().ToLowerInvariant();
        if (s.Length > 0) q = q.Where(d => d.SearchBlob.Contains(s) || d.DisplayName.ToLowerInvariant().Contains(s));
        return q.ToList();
    }

    private void RebuildSelectedDetails()
    {
        SelectedPorts.Clear();
        SelectedServices.Clear();
        SelectedHttp.Clear();
        SelectedUpnp.Clear();
        _detailState = SelectedDevice is { } sel ? DetailState(sel) : "";
        if (SelectedDevice is not { } d) return;
        foreach (var p in d.OpenPorts) SelectedPorts.Add(p);
        foreach (var s in d.Services) SelectedServices.Add(s);
        foreach (var h in d.Http) SelectedHttp.Add(h);
        foreach (var u in d.Upnp) SelectedUpnp.Add(u);
        OnPropertyChanged(nameof(SelectedDevice));
        OnPropertyChanged(nameof(DetailVisible));
        OnPropertyChanged(nameof(SelectedOsGuess));
        OnPropertyChanged(nameof(SelectedHistoryText));
        OnPropertyChanged(nameof(HasServices));
    }

    public bool HasServices => SelectedServices.Count > 0;

    private void RefreshHistory()
    {
        KnownDevices.Clear();
        foreach (var k in _history.SortedKnown) KnownDevices.Add(k);
        Scans.Clear();
        foreach (var s in _history.Scans) Scans.Add(s);
        OnPropertyChanged(nameof(HistoryCountText));
        OnPropertyChanged(nameof(SelectedHistoryText));
    }

    // MARK: Wake-on-LAN

    private void WakeDevice(string? mac, string? name)
    {
        if (string.IsNullOrEmpty(mac)) { Toast?.Invoke("Keine MAC-Adresse bekannt"); return; }
        var targets = new List<string>();
        if (_scanner.Network is { } net && WakeOnLan.Broadcast(net) is { } b) targets.Add(b);
        bool ok = WakeOnLan.Wake(mac!, targets);
        Toast?.Invoke(ok ? $"Magic Packet an „{name}“ gesendet ({mac})" : $"Ungültige MAC-Adresse: {mac}");
    }

    public bool IsOnline(KnownDevice k) => _scanner.SortedDevices.Any(d => HistoryStore.KeyFor(d) == k.Key);

    // MARK: Export

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public void DumpJson(string path) =>
        File.WriteAllText(path, JsonSerializer.Serialize(_scanner.SortedDevices, JsonOpts));

    private async void ExportJson(object? _)
    {
        var path = await FilePicker.SaveAsync("RedScan.json", "JSON", ".json");
        if (path is null) return;
        try { await File.WriteAllTextAsync(path, JsonSerializer.Serialize(_scanner.SortedDevices, JsonOpts)); Toast?.Invoke("Als JSON gespeichert"); }
        catch (Exception e) { Toast?.Invoke("Export fehlgeschlagen: " + e.Message); }
    }

    private async void ExportCsv(object? _)
    {
        var path = await FilePicker.SaveAsync("RedScan.csv", "CSV", ".csv");
        if (path is null) return;
        static string Esc(string? s) => "\"" + (s ?? "").Replace("\"", "\"\"") + "\"";
        var sb = new StringBuilder();
        sb.AppendLine("IP;Name;Typ;MAC;Hersteller;Hostname;mDNS;NetBIOS;OS;Latenz ms;Offene Ports;Dienste");
        foreach (var d in _scanner.SortedDevices)
            sb.AppendLine(string.Join(";", new[]
            {
                d.Ip, d.DisplayName, d.Kind.Label(), d.Mac, d.Vendor, d.Hostname, d.MdnsName, d.NetbiosName, d.OsGuess,
                d.LatencyMs?.ToString("F1"),
                string.Join(" ", d.OpenPorts.Select(p => p.Port)),
                string.Join(", ", d.Services.Select(s => s.TypeLabel))
            }.Select(Esc)));
        try { await File.WriteAllTextAsync(path, sb.ToString()); Toast?.Invoke("Als CSV gespeichert"); }
        catch (Exception e) { Toast?.Invoke("Export fehlgeschlagen: " + e.Message); }
    }

    // MARK: Eigenschaften

    private Device? _selectedDevice;
    public Device? SelectedDevice
    {
        get => _selectedDevice;
        set { if (_selectedDevice != value) { _selectedDevice = value; RebuildSelectedDetails(); OnPropertyChanged(); OnPropertyChanged(nameof(DetailVisible)); } }
    }

    private bool _showHistory;
    public bool ShowHistory
    {
        get => _showHistory;
        set { if (_showHistory != value) { _showHistory = value; OnPropertyChanged(); OnPropertyChanged(nameof(DevicesVisible)); OnPropertyChanged(nameof(HistoryVisible)); OnPropertyChanged(nameof(DetailVisible)); } }
    }

    private string? _searchText;
    public string? SearchText { get => _searchText; set { _searchText = value; OnPropertyChanged(); Refresh(); } }

    private DeviceKind? _kindFilter;
    public DeviceKind? KindFilter { get => _kindFilter; set { _kindFilter = value; OnPropertyChanged(); Refresh(); } }

    private string _phase = "Bereit";
    public string Phase { get => _phase; private set { _phase = value; OnPropertyChanged(); } }

    private double _progress;
    public double Progress { get => _progress; private set { _progress = value; OnPropertyChanged(); } }

    public bool IsScanning => _scanner.IsScanning;
    public string ScanButtonText => _scanner.IsScanning ? "Scan abbrechen" : "Netzwerk scannen";
    public int DeviceCount => _scanner.DeviceCount;
    public int TotalOpenPorts => _scanner.TotalOpenPorts;
    public int TotalServices => _scanner.TotalServices;
    public bool ArpBlocked => _scanner.ArpBlocked;

    public bool DevicesVisible => !ShowHistory;
    public bool HistoryVisible => ShowHistory;
    public bool DetailVisible => !ShowHistory && SelectedDevice != null;

    public string Subtitle
    {
        get
        {
            if (_scanner.DeviceCount == 0) return _scanner.IsScanning ? "Suche läuft …" : "Noch kein Scan durchgeführt";
            return $"{_scanner.DeviceCount} Geräte · {_scanner.Network?.Cidr}";
        }
    }

    public string HistoryCountText => $"{_history.Known.Count} bekannte Geräte · {_history.Scans.Count} Scans";

    public string? SelectedOsGuess => SelectedDevice?.OsGuess;
    public string SelectedHistoryText
    {
        get
        {
            if (SelectedDevice is null) return "";
            var k = _history.KnownFor(SelectedDevice);
            if (k is null) return "";
            return $"Zuerst {k.FirstSeen:dd.MM.yyyy HH:mm} · zuletzt {k.LastSeen:dd.MM.yyyy HH:mm} · {k.SeenCount}× gesehen";
        }
    }

    // Netzwerk-Infos (für die Seitenleiste)
    public string NetInterface => _scanner.Network?.Interface ?? "–";
    public string NetSsid => _scanner.Network?.Ssid ?? "";
    public bool HasSsid => !string.IsNullOrEmpty(_scanner.Network?.Ssid);
    public string NetIp => _scanner.Network?.Ip ?? "–";
    public string NetMac => _scanner.Network?.Mac ?? "–";
    public string NetCidr => _scanner.Network?.Cidr ?? "–";
    public string NetGateway => _scanner.Network?.Gateway ?? "–";
    public string NetDns => _scanner.Network != null ? string.Join(", ", _scanner.Network.Dns) : "–";
    public string NetHosts => _scanner.Network != null ? $"{_scanner.Network.Hosts.Count:N0} Adressen" : "–";
    public string NetNote => _scanner.Network?.Note ?? "";
    public bool HasNote => !string.IsNullOrEmpty(_scanner.Network?.Note);

    private void RaiseNetwork()
    {
        foreach (var p in new[] { nameof(NetInterface), nameof(NetSsid), nameof(HasSsid), nameof(NetIp), nameof(NetMac),
            nameof(NetCidr), nameof(NetGateway), nameof(NetDns), nameof(NetHosts), nameof(NetNote), nameof(HasNote), nameof(Subtitle) })
            OnPropertyChanged(p);
    }

    public void Select(Device d) => SelectedDevice = d;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
