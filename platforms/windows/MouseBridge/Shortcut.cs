// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

[Flags]
internal enum ShortcutModifiers
{
    None = 0,
    Control = 1,
    Shift = 2,
    Alt = 4,
    Meta = 8,
}

internal sealed record Shortcut(string Canonical, ShortcutModifiers Modifiers, ushort VirtualKey, bool IsPassThrough, bool IsNone)
{
    private static readonly Dictionary<string, ushort> Keys = BuildKeys();

    public static bool TryParse(string? specification, out Shortcut? shortcut)
    {
        string value = (specification ?? string.Empty).Trim().ToLowerInvariant();
        if (value.Length == 0)
        {
            shortcut = new Shortcut(string.Empty, ShortcutModifiers.None, 0, true, false);
            return true;
        }

        if (value == "none")
        {
            shortcut = new Shortcut("none", ShortcutModifiers.None, 0, false, true);
            return true;
        }

        string[] parts = value.Split('+', StringSplitOptions.None);
        if (parts.Length == 0 || parts.Any(string.IsNullOrWhiteSpace) || !Keys.TryGetValue(parts[^1], out ushort key))
        {
            shortcut = null;
            return false;
        }

        ShortcutModifiers modifiers = ShortcutModifiers.None;
        List<string> canonicalModifiers = [];
        foreach (string rawModifier in parts[..^1])
        {
            (ShortcutModifiers flag, string canonical) = rawModifier switch
            {
                "ctrl" or "control" => (ShortcutModifiers.Control, "ctrl"),
                "shift" => (ShortcutModifiers.Shift, "shift"),
                "alt" or "opt" or "option" => (ShortcutModifiers.Alt, "alt"),
                "meta" or "cmd" or "command" or "win" => (ShortcutModifiers.Meta, "meta"),
                _ => (ShortcutModifiers.None, string.Empty),
            };
            if (flag == ShortcutModifiers.None || modifiers.HasFlag(flag))
            {
                shortcut = null;
                return false;
            }
            modifiers |= flag;
            canonicalModifiers.Add(canonical);
        }

        string canonicalValue = string.Join('+', canonicalModifiers.Append(parts[^1]));
        shortcut = new Shortcut(canonicalValue, modifiers, key, false, false);
        return true;
    }

    private static Dictionary<string, ushort> BuildKeys()
    {
        Dictionary<string, ushort> result = new(StringComparer.Ordinal);
        for (char value = 'a'; value <= 'z'; value++) result[value.ToString()] = char.ToUpperInvariant(value);
        for (char value = '0'; value <= '9'; value++) result[value.ToString()] = value;
        for (int index = 1; index <= 24; index++) result[$"f{index}"] = (ushort)(0x6F + index);
        result["left"] = 0x25;
        result["up"] = 0x26;
        result["right"] = 0x27;
        result["down"] = 0x28;
        result["enter"] = 0x0D;
        result["tab"] = 0x09;
        result["space"] = 0x20;
        result["delete"] = 0x2E;
        result["backspace"] = 0x08;
        result["escape"] = 0x1B;
        result["home"] = 0x24;
        result["end"] = 0x23;
        result["pageup"] = 0x21;
        result["pagedown"] = 0x22;
        result["insert"] = 0x2D;
        result["-"] = 0xBD;
        result["="] = 0xBB;
        result["["] = 0xDB;
        result["]"] = 0xDD;
        result[";"] = 0xBA;
        result["'"] = 0xDE;
        result[","] = 0xBC;
        result["."] = 0xBE;
        result["/"] = 0xBF;
        result["\\"] = 0xDC;
        return result;
    }
}
