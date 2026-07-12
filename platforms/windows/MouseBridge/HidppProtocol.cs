// SPDX-License-Identifier: GPL-3.0-or-later
// Adjustable-DPI range decoding is adapted from Solaar, GPL-2.0-or-later.
// See the repository THIRD_PARTY_NOTICES.md and LICENSES/GPL-2.0.txt.

namespace MouseBridge.Windows;

internal static class HidppProtocol
{
    public const byte LongReportId = 0x11;
    public const byte SoftwareId = 0x0A;
    public const ushort AdjustableDpiFeature = 0x2201;
    public const int FrameLength = 20;

    public static byte[] BuildRequest(byte featureIndex, byte function, ReadOnlySpan<byte> parameters, int reportLength)
    {
        if (reportLength < FrameLength) throw new ArgumentOutOfRangeException(nameof(reportLength));
        byte[] frame = new byte[reportLength];
        frame[0] = LongReportId;
        frame[1] = 0xFF;
        frame[2] = featureIndex;
        frame[3] = (byte)(((function & 0x0F) << 4) | SoftwareId);
        parameters[..Math.Min(parameters.Length, 16)].CopyTo(frame.AsSpan(4));
        return frame;
    }

    public static bool TryParse(ReadOnlySpan<byte> report, out HidppMessage message)
    {
        message = default;
        if (report.Length < 4 || report[0] is not (0x10 or LongReportId)) return false;
        if (report[2] == 0xFF)
        {
            if (report.Length < 7) return false;
            byte originalFunctionSoftware = report[4];
            message = new HidppMessage(
                report[1],
                report[3],
                (byte)(originalFunctionSoftware >> 4),
                (byte)(originalFunctionSoftware & 0x0F),
                report[5..].ToArray(),
                true,
                report[5]);
            return true;
        }

        byte functionSoftware = report[3];
        message = new HidppMessage(
            report[1],
            report[2],
            (byte)(functionSoftware >> 4),
            (byte)(functionSoftware & 0x0F),
            report[4..].ToArray(),
            false,
            0);
        return true;
    }

    public static IReadOnlyList<int> DecodeDpiList(ReadOnlySpan<byte> bytes)
    {
        List<int> values = [];
        int index = 0;
        while (index + 1 < bytes.Length)
        {
            int value = (bytes[index] << 8) | bytes[index + 1];
            if (value == 0) break;
            if ((value >> 13) == 0b111)
            {
                int step = value & 0x1FFF;
                if (step <= 0 || values.Count == 0 || index + 3 >= bytes.Length) break;
                int maximum = (bytes[index + 2] << 8) | bytes[index + 3];
                int previous = values[^1];
                if (maximum <= previous) break;
                for (long candidate = (long)previous + step; candidate <= maximum; candidate += step)
                {
                    if (candidate > 10000) break;
                    values.Add((int)candidate);
                }
                index += 4;
            }
            else
            {
                values.Add(value);
                index += 2;
            }
        }
        return values.Where(value => value is >= 100 and <= 10000).Distinct().Order().ToArray();
    }
}

internal readonly record struct HidppMessage(
    byte DeviceIndex,
    byte FeatureIndex,
    byte Function,
    byte SoftwareId,
    byte[] Parameters,
    bool IsError,
    byte ErrorCode);
