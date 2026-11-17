using System.Net.NetworkInformation;

namespace RedScan.Core.Probes;

public readonly record struct PingResult(string Ip, int Ttl, double TimeMs);

public static class PingSweep
{
    /// <summary>Pingt viele Adressen parallel. Antworten werden sofort per Callback gemeldet.
    /// Nebeneffekt: füllt den ARP-Cache des Systems.</summary>
    public static async Task RunAsync(
        IReadOnlyList<string> hosts,
        Action<PingResult> onReply,
        Action<int>? onProgress = null,
        int concurrency = 256,
        int timeoutMs = 700,
        CancellationToken ct = default)
    {
        using var gate = new SemaphoreSlim(concurrency);
        int done = 0;
        var tasks = new List<Task>(hosts.Count);
        foreach (var host in hosts)
        {
            if (ct.IsCancellationRequested) break;
            await gate.WaitAsync(ct).ConfigureAwait(false);
            tasks.Add(Task.Run(async () =>
            {
                try
                {
                    using var ping = new Ping();
                    var reply = await ping.SendPingAsync(host, timeoutMs).ConfigureAwait(false);
                    if (reply.Status == IPStatus.Success)
                    {
                        int ttl = reply.Options?.Ttl ?? 0;
                        onReply(new PingResult(host, ttl, reply.RoundtripTime));
                    }
                }
                catch { }
                finally
                {
                    gate.Release();
                    int d = Interlocked.Increment(ref done);
                    onProgress?.Invoke(d);
                }
            }, ct));
        }
        try { await Task.WhenAll(tasks).ConfigureAwait(false); } catch { }
    }

    public static async Task<PingResult?> OnceAsync(string ip, int timeoutMs = 900)
    {
        try
        {
            using var ping = new Ping();
            var reply = await ping.SendPingAsync(ip, timeoutMs).ConfigureAwait(false);
            if (reply.Status == IPStatus.Success)
                return new PingResult(ip, reply.Options?.Ttl ?? 0, reply.RoundtripTime);
        }
        catch { }
        return null;
    }
}
