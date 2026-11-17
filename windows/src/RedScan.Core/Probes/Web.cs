using System.Net;
using System.Net.Security;
using System.Text.RegularExpressions;

namespace RedScan.Core.Probes;

public static class Web
{
    public static async Task<HttpInfo?> FetchAsync(string ip, int port, bool tls, int timeoutMs = 4000, CancellationToken ct = default)
    {
        string? certSummary = null;
        using var handler = new HttpClientHandler
        {
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 3,
            ServerCertificateCustomValidationCallback = (_, cert, _, _) =>
            {
                if (cert != null) certSummary = cert.Subject;
                return true; // selbstsignierte Zertifikate akzeptieren
            }
        };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromMilliseconds(timeoutMs) };
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0) RedScan/1.0");

        var url = $"{(tls ? "https" : "http")}://{ip}:{port}/";
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeoutMs);
            using var resp = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
            string body = "";
            try
            {
                var bytes = await resp.Content.ReadAsByteArrayAsync(cts.Token).ConfigureAwait(false);
                body = System.Text.Encoding.UTF8.GetString(bytes, 0, Math.Min(bytes.Length, 300_000));
            }
            catch { }

            string? title = null;
            var m = Regex.Match(body, @"<title[^>]*>(.*?)</title>", RegexOptions.IgnoreCase | RegexOptions.Singleline);
            if (m.Success) title = Text.Clean(Text.DecodeEntities(m.Groups[1].Value)).NilIfEmpty();

            return new HttpInfo
            {
                Port = port,
                Tls = tls,
                Status = (int)resp.StatusCode,
                Server = resp.Headers.TryGetValues("Server", out var sv) ? string.Join(" ", sv) : null,
                PoweredBy = resp.Headers.TryGetValues("X-Powered-By", out var pb) ? string.Join(" ", pb) : null,
                Title = title != null && title.Length > 120 ? title[..120] : title,
                Certificate = certSummary
            };
        }
        catch
        {
            // Selbst bei abgebrochenem Request kann das Zertifikat schon vorliegen
            return certSummary != null ? new HttpInfo { Port = port, Tls = tls, Certificate = certSummary } : null;
        }
    }

    public static async Task<string?> PublicIpAsync()
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            return (await client.GetStringAsync("https://api.ipify.org").ConfigureAwait(false)).Trim();
        }
        catch { return null; }
    }
}
