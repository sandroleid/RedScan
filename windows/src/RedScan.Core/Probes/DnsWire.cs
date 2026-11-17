using System.Text;

namespace RedScan.Core.Probes;

/// <summary>Minimaler DNS-Nachrichten-Parser (für mDNS).</summary>
public static class DnsWire
{
    public record Record(string Name, int Type, byte[] Data, int DataOffset, int DataLen);

    public static byte[] EncodeName(string name)
    {
        var outBytes = new List<byte>();
        foreach (var label in name.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            var b = Encoding.UTF8.GetBytes(label);
            outBytes.Add((byte)b.Length);
            outBytes.AddRange(b);
        }
        outBytes.Add(0);
        return outBytes.ToArray();
    }

    public static byte[] BuildQuery(string name, ushort type, bool unicastResponse)
    {
        var msg = new List<byte> { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        msg.AddRange(EncodeName(name));
        msg.Add((byte)(type >> 8));
        msg.Add((byte)(type & 0xFF));
        ushort qclass = (ushort)(unicastResponse ? 0x8001 : 0x0001);
        msg.Add((byte)(qclass >> 8));
        msg.Add((byte)(qclass & 0xFF));
        return msg.ToArray();
    }

    /// <summary>Liest einen (ggf. komprimierten) DNS-Namen ab offset. Bewegt offset hinter den Namen.</summary>
    public static string? ReadName(byte[] b, ref int offset)
    {
        var labels = new List<string>();
        int pos = offset;
        bool jumped = false;
        int hops = 0;
        while (pos < b.Length)
        {
            int len = b[pos];
            if (len == 0) { pos++; break; }
            if ((len & 0xC0) == 0xC0)
            {
                if (pos + 1 >= b.Length || hops >= 20) return null;
                int ptr = ((len & 0x3F) << 8) | b[pos + 1];
                if (!jumped) offset = pos + 2;
                jumped = true; hops++;
                pos = ptr;
                continue;
            }
            if (pos + 1 + len > b.Length) return null;
            labels.Add(Encoding.UTF8.GetString(b, pos + 1, len));
            pos += 1 + len;
        }
        if (!jumped) offset = pos;
        return string.Join(".", labels);
    }

    public static List<Record> ParseRecords(byte[] b)
    {
        var records = new List<Record>();
        if (b.Length < 12) return records;
        int qd = (b[4] << 8) | b[5];
        int an = (b[6] << 8) | b[7];
        int ns = (b[8] << 8) | b[9];
        int ar = (b[10] << 8) | b[11];
        int off = 12;
        for (int i = 0; i < qd; i++)
        {
            if (ReadName(b, ref off) is null) return records;
            off += 4;
        }
        int total = an + ns + ar;
        for (int i = 0; i < total; i++)
        {
            var name = ReadName(b, ref off);
            if (name is null || off + 10 > b.Length) break;
            int type = (b[off] << 8) | b[off + 1];
            int rdlen = (b[off + 8] << 8) | b[off + 9];
            off += 10;
            if (off + rdlen > b.Length) break;
            records.Add(new Record(name, type, b, off, rdlen));
            off += rdlen;
        }
        return records;
    }
}
