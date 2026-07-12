// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

internal static class ScrollTransform
{
    public const int WheelDelta = 120;

    public static int? Transform(int delta, bool reverse, int lines, int systemLinesPerDetent = 1)
    {
        int normalizedLines = Math.Clamp(lines, 0, 20);
        bool discreteSingleStep = Math.Abs(delta) == WheelDelta;
        if (normalizedLines > 0 && discreteSingleStep)
        {
            int direction = Math.Sign(delta) * (reverse ? -1 : 1);
            int systemLines = Math.Max(1, systemLinesPerDetent);
            return direction * Math.Max(1, (int)Math.Round((double)normalizedLines * WheelDelta / systemLines));
        }

        return reverse ? -delta : null;
    }
}
