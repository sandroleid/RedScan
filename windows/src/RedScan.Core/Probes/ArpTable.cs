using System.Runtime.InteropServices;

namespace RedScan.Core.Probes;

/// <summary>Liest die ARP-Tabelle über die Windows-IP-Helper-API (iphlpapi, GetIpNetTable).</summary>
public static class ArpTable
{
    public readonly record struct Entry(string Ip, string Mac);

    [DllImport("iphlpapi.dll", SetLastError = true)]
    private static extern int GetIpNetTable(IntPtr pIpNetTable, ref int pdwSize, bool bOrder);

    private const int ERROR_INSUFFICIENT_BUFFER = 122;

    public static List<Entry> Read()
    {
        var result = new List<Entry>();
        int size = 0;
        if (GetIpNetTable(IntPtr.Zero, ref size, false) != ERROR_INSUFFICIENT_BUFFER || size <= 0)
            return result;

        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            if (GetIpNetTable(buffer, ref size, false) != 0) return result;
            int count = Marshal.ReadInt32(buffer);
            // MIB_IPNETROW: dwIndex(4) + dwPhysAddrLen(4) + bPhysAddr(8) + dwAddr(4) + dwType(4) = 24 Bytes
            const int rowSize = 24;
            IntPtr rowPtr = buffer + 4;
            for (int i = 0; i < count; i++)
            {
                int physLen = Marshal.ReadInt32(rowPtr + 4);
                var macBytes = new byte[8];
                Marshal.Copy(rowPtr + 8, macBytes, 0, 8);
                uint addr = (uint)Marshal.ReadInt32(rowPtr + 16);
                int type = Marshal.ReadInt32(rowPtr + 20);
                rowPtr += rowSize;

                if (physLen != 6) continue;          // nur Ethernet-MACs
                if (type == 2) continue;              // 2 = invalid
                var mac = IPv4.MacFromBytes(macBytes);
                if (mac == "FF:FF:FF:FF:FF:FF" || mac == "00:00:00:00:00:00" || mac.StartsWith("01:00:5E")) continue;
                result.Add(new Entry(IPv4.FromNetworkOrder(addr), mac));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
        return result;
    }
}
