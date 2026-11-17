using RedScan.Core;
using RedScan.Core.Probes;
using Xunit;

namespace RedScan.Tests;

public class IPv4Tests
{
    [Fact]
    public void Hosts_Slash24_Has254()
        => Assert.Equal(254, IPv4.Hosts("192.168.1.0/24")!.Count);

    [Fact]
    public void Hosts_Slash28_FirstAndCount()
    {
        var h = IPv4.Hosts("172.20.10.0/28")!;
        Assert.Equal("172.20.10.1", h[0]);
        Assert.Equal(14, h.Count);
    }

    [Fact]
    public void Hosts_TooBigOrInvalid_Null()
    {
        Assert.Null(IPv4.Hosts("10.0.0.0/8"));
        Assert.Null(IPv4.Hosts("quatsch"));
    }

    [Fact]
    public void Hosts_Slash32_SingleAddress()
        => Assert.Equal(new[] { "10.0.0.7" }, IPv4.Hosts("10.0.0.7/32")!.ToArray());

    [Fact]
    public void ToUInt32_RoundTrip()
    {
        var v = IPv4.ToUInt32("192.168.164.141")!.Value;
        Assert.Equal("192.168.164.141", IPv4.ToString(v));
    }

    [Fact]
    public void FromNetworkOrder_Works()
    {
        // 1.2.3.4 im Windows-Byteorder (little endian) = 0x04030201
        Assert.Equal("1.2.3.4", IPv4.FromNetworkOrder(0x04030201u));
    }

    [Fact]
    public void PrefixLength_Correct()
    {
        Assert.Equal(24, IPv4.PrefixLength(IPv4.ToUInt32("255.255.255.0")!.Value));
        Assert.Equal(17, IPv4.PrefixLength(IPv4.ToUInt32("255.255.128.0")!.Value));
    }

    [Fact]
    public void NormalizeMac_PadsAndUppercases()
        => Assert.Equal("01:0A:5E:00:00:FB", IPv4.NormalizeMac("1:a:5e:0:0:fb"));
}

public class VendorDbTests
{
    [Fact]
    public void Database_Loaded()
        => Assert.True(VendorDb.Shared.Count > 50000, $"nur {VendorDb.Shared.Count} Einträge");

    [Fact]
    public void Lookup_Apple()
        => Assert.Contains("Apple", VendorDb.Shared.Lookup("F0:B4:79:11:22:33") ?? "");

    [Fact]
    public void Lookup_RaspberryPi()
        => Assert.Contains("Raspberry", VendorDb.Shared.Lookup("B8:27:EB:00:00:01") ?? "");

    [Fact]
    public void Randomized_Detection()
    {
        Assert.True(VendorDb.IsRandomized("96:52:40:18:A3:C7"));
        Assert.False(VendorDb.IsRandomized("F0:B4:79:00:00:00"));
    }
}

public class WakeOnLanTests
{
    [Fact]
    public void BuildPacket_CorrectShape()
    {
        var p = WakeOnLan.BuildPacket("AA:BB:CC:DD:EE:FF")!;
        Assert.Equal(102, p.Length);
        Assert.All(p.Take(6), b => Assert.Equal(0xFF, b));
        Assert.Equal(new byte[] { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }, p.Skip(6).Take(6).ToArray());
        Assert.Equal(new byte[] { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }, p.Skip(96).Take(6).ToArray());
    }

    [Fact]
    public void BuildPacket_InvalidMac_Null()
        => Assert.Null(WakeOnLan.BuildPacket("zz"));

    [Fact]
    public void Broadcast_Computed()
    {
        var net = new NetworkInfo { Ip = "192.168.164.141", Netmask = "255.255.128.0" };
        Assert.Equal("192.168.255.255", WakeOnLan.Broadcast(net));
    }
}

public class ClassifierTests
{
    private static Device Dev(Action<Device> f) { var d = new Device { Ip = "10.0.0.9" }; f(d); return d; }

    [Fact] public void Printer() => Assert.Equal(DeviceKind.Printer, Classifier.Classify(Dev(d => d.OpenPorts.Add(new OpenPort { Port = 9100 }))));
    [Fact] public void Phone_ByModel() => Assert.Equal(DeviceKind.Phone, Classifier.Classify(Dev(d => d.Model = "iPhone15,2")));
    [Fact] public void Windows() => Assert.Equal(DeviceKind.Computer, Classifier.Classify(Dev(d => { d.OpenPorts.Add(new OpenPort { Port = 3389 }); d.OpenPorts.Add(new OpenPort { Port = 445 }); })));
    [Fact] public void Router_ByVendor() => Assert.Equal(DeviceKind.Router, Classifier.Classify(Dev(d => { d.Vendor = "AVM GmbH"; d.OpenPorts.Add(new OpenPort { Port = 80 }); })));
    [Fact] public void Gateway() => Assert.Equal(DeviceKind.Router, Classifier.Classify(Dev(d => d.IsGateway = true)));
    [Fact] public void Chromecast() => Assert.Equal(DeviceKind.Tv, Classifier.Classify(Dev(d => d.Services.Add(new BonjourService { Name = "TV", Type = "_googlecast._tcp.", Port = 8009 }))));

    [Fact] public void PrettyModel() => Assert.Equal("MacBook Pro (MacBookPro18,3)", Classifier.PrettyModel("MacBookPro18,3"));

    [Fact]
    public void OsGuess_WindowsByTtl()
        => Assert.StartsWith("Windows", Dev(d => d.Ttl = 128).OsGuess);

    [Fact]
    public void DisplayName_FromMdns()
        => Assert.Equal("Wohnzimmer", Dev(d => d.MdnsName = "Wohnzimmer.local").DisplayName);

    [Fact]
    public void MacFromServices_RaopFallback()
    {
        var mac = Scanner.MacFromServices(new List<BonjourService>
        {
            new() { Name = "AABBCC112233@Wohnzimmer", Type = "_raop._tcp.", Port = 7000 }
        });
        Assert.Equal("AA:BB:CC:11:22:33", mac);
    }
}

public class DnsWireTests
{
    [Fact]
    public void ParsesReversePtr()
    {
        // Reverse-PTR-Antwort: 5.10.20.172.in-addr.arpa → Test-PC.local
        var msg = new List<byte> { 0, 0, 0x84, 0, 0, 1, 0, 1, 0, 0, 0, 0 };
        msg.AddRange(DnsWire.EncodeName("5.10.20.172.in-addr.arpa"));
        msg.AddRange(new byte[] { 0, 12, 0, 1 });            // QTYPE PTR, QCLASS IN
        msg.AddRange(new byte[] { 0xC0, 12, 0, 12, 0, 1, 0, 0, 0, 120 }); // Pointer auf Frage, PTR, IN, TTL
        var rd = DnsWire.EncodeName("Test-PC.local");
        msg.Add(0); msg.Add((byte)rd.Length);
        msg.AddRange(rd);

        var recs = DnsWire.ParseRecords(msg.ToArray());
        var ptr = recs.FirstOrDefault(r => r.Type == 12);
        Assert.NotNull(ptr);
        Assert.Equal("5.10.20.172.in-addr.arpa", ptr!.Name);
        int o = ptr.DataOffset;
        Assert.Equal("Test-PC.local", DnsWire.ReadName(ptr.Data, ref o));
    }

    [Fact]
    public void ParsesARecord()
    {
        var msg = new List<byte> { 0, 0, 0x84, 0, 0, 1, 0, 1, 0, 0, 0, 0 };
        msg.AddRange(DnsWire.EncodeName("host.local"));
        msg.AddRange(new byte[] { 0, 1, 0, 1 });
        msg.AddRange(new byte[] { 0xC0, 12, 0, 1, 0, 1, 0, 0, 0, 120, 0, 4, 192, 168, 1, 50 });
        var a = DnsWire.ParseRecords(msg.ToArray()).First(r => r.Type == 1);
        Assert.Equal(4, a.DataLen);
        Assert.Equal(192, a.Data[a.DataOffset]);
        Assert.Equal(50, a.Data[a.DataOffset + 3]);
    }
}

public class TextTests
{
    [Fact] public void Clean_RemovesControl() => Assert.Equal("SSH-2.0", Text.Clean("SSH-2.0\r\n\u0001"));
    [Fact] public void DecodeEntities_Works() => Assert.Equal("A & B ä", Text.DecodeEntities("A &amp; B &auml;"));
}

public class WindowsApiTests
{
    // Diese Tests laufen auf echtem Windows (GitHub-Runner) und prüfen, dass die
    // nativen Aufrufe funktionieren, ohne Ausnahmen auszulösen.

    [Fact]
    public void ArpTable_DoesNotThrow()
    {
        var entries = ArpTable.Read();
        Assert.NotNull(entries);
    }

    [Fact]
    public void NetworkDetector_DoesNotThrow()
    {
        var ex = Record.Exception(() => NetworkDetector.Detect());
        Assert.Null(ex);
    }

    [Fact]
    public void ComputerName_Available()
        => Assert.False(string.IsNullOrEmpty(Environment.MachineName));
}

public class NetworkProbeTests
{
    [Fact]
    public void ProxyMacs_DetectsSharedMac()
    {
        var entries = new List<ArpTable.Entry>();
        for (int i = 1; i <= 40; i++) entries.Add(new ArpTable.Entry($"10.1.0.{i}", "12:34:56:78:9A:BC"));
        entries.Add(new ArpTable.Entry("10.1.0.200", "AA:BB:CC:00:00:01"));
        var proxy = ArpTable.ProxyMacs(entries);
        Assert.Contains("12:34:56:78:9A:BC", proxy);
        Assert.DoesNotContain("AA:BB:CC:00:00:01", proxy);
    }

    [Fact]
    public async Task Connect_OpenPort_Succeeds()
    {
        var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        listener.Start();
        int port = ((System.Net.IPEndPoint)listener.LocalEndpoint).Port;
        try
        {
            var open = await Ports.ScanAsync("127.0.0.1", new[] { port });
            Assert.Equal(new[] { port }, open.ToArray());
        }
        finally { listener.Stop(); }
    }

    [Fact]
    public async Task Connect_Timeout_ReturnsNullWithoutUnobservedExceptions()
    {
        int unobserved = 0;
        EventHandler<UnobservedTaskExceptionEventArgs> h = (_, e) => { Interlocked.Increment(ref unobserved); e.SetObserved(); };
        TaskScheduler.UnobservedTaskException += h;
        try
        {
            // 192.0.2.0/24 ist ein reserviertes Test-Netz – Verbindungen laufen ins Leere
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var open = await Ports.ScanAsync("192.0.2.1", new[] { 80, 443, 22, 8080 }, timeoutMs: 400);
            sw.Stop();
            Assert.Empty(open);
            Assert.True(sw.ElapsedMilliseconds < 5000, $"Scan dauerte {sw.ElapsedMilliseconds} ms");
            GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
            await Task.Delay(300);
            GC.Collect(); GC.WaitForPendingFinalizers();
            Assert.Equal(0, unobserved);
        }
        finally { TaskScheduler.UnobservedTaskException -= h; }
    }
}

public class HistoryTests
{
    [Fact]
    public void RecordAndReload_RoundTrips()
    {
        var tmp = Path.Combine(Path.GetTempPath(), $"redscan_hist_{Guid.NewGuid():N}.json");
        try
        {
            var net = new NetworkInfo { Cidr = "192.168.1.0/24", Ssid = "Test" };
            var store = new HistoryStore(tmp);
            var devs = new List<Device>
            {
                new() { Ip = "192.168.1.1", Mac = "AA:BB:CC:00:00:01", Kind = DeviceKind.Router },
                new() { Ip = "192.168.1.5", Mac = "AA:BB:CC:00:00:05", Kind = DeviceKind.Computer },
            };
            store.Record(devs, net, 12.3);
            Assert.Equal(2, store.Known.Count);
            Assert.Single(store.Scans);
            // Erster Scan eines Netzes → nichts als "neu" markiert
            Assert.Empty(store.NewInLastScan);

            // Zweiter Scan mit einem zusätzlichen Gerät → genau das ist neu
            devs.Add(new Device { Ip = "192.168.1.9", Mac = "AA:BB:CC:00:00:09", Kind = DeviceKind.Phone });
            store.Record(devs, net, 10.0);
            Assert.Contains("AA:BB:CC:00:00:09", store.NewInLastScan);
            Assert.Equal(3, store.Known.Count);

            var reloaded = new HistoryStore(tmp);
            Assert.Equal(3, reloaded.Known.Count);
            Assert.Equal(2, reloaded.Scans.Count);
        }
        finally { if (File.Exists(tmp)) File.Delete(tmp); }
    }
}
