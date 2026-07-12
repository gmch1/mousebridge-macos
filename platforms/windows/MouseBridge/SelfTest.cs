// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

internal static class SelfTest
{
    public static int Run()
    {
        List<(string Name, Func<bool> Check)> checks =
        [
            ("shortcut empty pass-through", () => Parse("").IsPassThrough),
            ("shortcut none", () => Parse("none").IsNone),
            ("shortcut ctrl+r", () => Parse("ctrl+r").Canonical == "ctrl+r"),
            ("shortcut cmd canonicalizes to meta", () => Parse(" CMD+W ").Canonical == "meta+w"),
            ("shortcut multiple modifiers", () => Parse("ctrl+shift+z").Canonical == "ctrl+shift+z"),
            ("shortcut rejects unknown key", () => !Shortcut.TryParse("ctrl+not-a-key", out _)),
            ("shortcut rejects empty component", () => !Shortcut.TryParse("ctrl++r", out _)),
            ("shortcut rejects duplicate modifier", () => !Shortcut.TryParse("ctrl+control+r", out _)),
            ("vertical raw magnitude reversal", () => ScrollTransform.Transform(30, true, 0) == -30),
            ("discrete positive lines", () => ScrollTransform.Transform(120, false, 4) == 480),
            ("discrete negative reversed", () => ScrollTransform.Transform(-120, true, 4) == 480),
            ("logical lines respect Windows setting", () => ScrollTransform.Transform(120, false, 4, 3) == 160),
            ("scroll lines upper bound", () => ScrollTransform.Transform(120, false, 99) == 2400),
            ("continuous input not quantized", () => ScrollTransform.Transform(30, false, 20) is null),
            ("DPI compressed range", DpiCompressedRange),
            ("DPI explicit terminator", () => HidppProtocol.DecodeDpiList([0x03, 0x20, 0x06, 0x40, 0, 0, 0x0F, 0xA0]).SequenceEqual([800, 1600])),
            ("DPI invalid zero step", () => HidppProtocol.DecodeDpiList([0x01, 0x90, 0xE0, 0x00, 0x0F, 0xA0]).SequenceEqual([400])),
            ("config normalization", ConfigNormalization),
            ("configuration atomic save", ConfigAtomicSave),
            ("invalid external config keeps last valid", InvalidConfigFallback),
            ("injected flag ignored", () => MouseHook.ShouldIgnore(NativeMethods.LlMouseInjected, 0)),
            ("injection marker ignored", () => MouseHook.ShouldIgnore(0, MouseHook.InjectionMarker)),
            ("hardware event accepted", () => !MouseHook.ShouldIgnore(0, 0)),
            ("HID++ response parsing", HidppResponseParsing),
            ("HID++ error parsing", HidppErrorParsing),
        ];

        bool passed = true;
        foreach ((string name, Func<bool> check) in checks)
        {
            bool result;
            try { result = check(); }
            catch { result = false; }
            Console.WriteLine($"{(result ? "PASS" : "FAIL")} {name}");
            passed &= result;
        }
        return passed ? 0 : 1;
    }

    private static Shortcut Parse(string value) => Shortcut.TryParse(value, out Shortcut? shortcut)
        ? shortcut!
        : throw new InvalidOperationException();

    private static bool DpiCompressedRange()
    {
        IReadOnlyList<int> values = HidppProtocol.DecodeDpiList([0x01, 0x90, 0xE0, 0x64, 0x0F, 0xA0, 0, 0]);
        return values.Count == 37 && values[0] == 400 && values[^1] == 4000;
    }

    private static bool ConfigNormalization()
    {
        AppConfig config = new() { BackAction = " CMD+R ", ScrollLines = 99, Dpi = 1055 };
        AppConfig normalized = config.Normalize([400, 500, 600, 700, 800, 900, 1000, 1100]);
        return normalized.SchemaVersion == 1 && normalized.BackAction == "meta+r" && normalized.ScrollLines == 20 && normalized.Dpi == 1100;
    }

    private static bool ConfigAtomicSave()
    {
        string directory = Path.Combine(Path.GetTempPath(), $"MouseBridge-self-test-{Guid.NewGuid():N}");
        string path = Path.Combine(directory, "config.json");
        try
        {
            using ConfigStore store = new(configPath: path);
            AppConfig saved = store.Save(store.Current with { MiddleAction = "none", ScrollLines = 7 });
            using ConfigStore reloaded = new(configPath: path);
            return saved == reloaded.Current && !Directory.EnumerateFiles(directory, "*.tmp").Any();
        }
        finally
        {
            try { Directory.Delete(directory, true); } catch { }
        }
    }

    private static bool InvalidConfigFallback()
    {
        string directory = Path.Combine(Path.GetTempPath(), $"MouseBridge-self-test-{Guid.NewGuid():N}");
        string path = Path.Combine(directory, "config.json");
        try
        {
            using ConfigStore store = new(configPath: path);
            AppConfig valid = store.Save(store.Current with { BackAction = "none", ScrollLines = 8 });
            store.StartWatching();
            File.WriteAllText(path, "{ invalid json");
            bool observed = SpinWait.SpinUntil(() => store.LastError is not null, TimeSpan.FromSeconds(2));
            return observed && store.Current == valid;
        }
        finally
        {
            try { Directory.Delete(directory, true); } catch { }
        }
    }

    private static bool HidppResponseParsing()
    {
        byte[] report = new byte[20];
        report[0] = 0x11;
        report[1] = 0xFF;
        report[2] = 0x07;
        report[3] = 0x2A;
        report[4] = 0;
        report[5] = 0x03;
        report[6] = 0xE8;
        return HidppProtocol.TryParse(report, out HidppMessage message) &&
               !message.IsError && message.FeatureIndex == 7 && message.Function == 2 &&
               message.SoftwareId == HidppProtocol.SoftwareId && message.Parameters[1] == 3;
    }

    private static bool HidppErrorParsing()
    {
        byte[] report = [0x11, 0xFF, 0xFF, 0x07, 0x3A, 0x02, 0, 0];
        return HidppProtocol.TryParse(report, out HidppMessage message) && message.IsError &&
               message.FeatureIndex == 7 && message.Function == 3 && message.ErrorCode == 2;
    }
}
