using System.Net;

namespace RedScan.Core.Probes;

public static class ReverseDns
{
    public static async Task<Dictionary<string, string>> LookupAsync(IReadOnlyList<string> ips, int timeoutMs = 4000, CancellationToken ct = default)
    {
        var result = new Dictionary<string, string>();
        var lockObj = new object();
        using var overall = new CancellationTokenSource(timeoutMs);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, overall.Token);

        var tasks = ips.Select(async ip =>
        {
            try
            {
                var entry = await Dns.GetHostEntryAsync(ip, linked.Token).ConfigureAwait(false);
                if (!string.IsNullOrEmpty(entry.HostName) && entry.HostName != ip)
                    lock (lockObj) { result[ip] = entry.HostName; }
            }
            catch { }
        });
        try { await Task.WhenAll(tasks).ConfigureAwait(false); } catch { }
        return result;
    }
}
