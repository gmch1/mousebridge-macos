// SPDX-License-Identifier: GPL-3.0-or-later

using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace MouseBridge.Windows;

internal static class CommandLineInterface
{
    private static readonly JsonSerializerOptions PrettyJson = new() { WriteIndented = true };

    public static int Run(string[] arguments)
    {
        if (arguments.Length == 0) return 2;
        try
        {
            return arguments[0] switch
            {
                "config" => RunConfig(arguments[1..]),
                "diagnose" when arguments.Length == 1 => Diagnose(),
                "help" or "--help" or "-h" when arguments.Length == 1 => Help(0),
                _ => Fail($"unknown command: {arguments[0]}", 2),
            };
        }
        catch (ArgumentException exception) { return Fail(exception.Message, 2); }
        catch (Exception exception) { return Fail(exception.Message, 1); }
    }

    private static int RunConfig(string[] arguments)
    {
        if (arguments.SequenceEqual(["path"]))
        {
            Console.WriteLine(AppPaths.ConfigPath);
            return 0;
        }
        using ConfigStore store = new();
        if (store.LastError is not null) return Fail($"configuration is invalid: {store.LastError}", 1);
        if (arguments.SequenceEqual(["get"]))
        {
            Console.WriteLine(JsonSerializer.Serialize(store.Current, PrettyJson));
            return 0;
        }
        if (arguments.Length != 3 || arguments[0] != "set")
            return Fail("usage: MouseBridge config path|get|set <key> <value>", 2);

        string key = arguments[1];
        string value = arguments[2];
        AppConfig config = store.Current;
        switch (key)
        {
            case "middle": config = config with { MiddleAction = ParseAction(value) }; break;
            case "back": config = config with { BackAction = ParseAction(value) }; break;
            case "forward": config = config with { ForwardAction = ParseAction(value) }; break;
            case "reverse-vertical": config = config with { ReverseVerticalScroll = ParseBool(value) }; break;
            case "reverse-horizontal": config = config with { ReverseHorizontalScroll = ParseBool(value) }; break;
            case "scroll-lines":
                if (!int.TryParse(value, out int lines) || lines is < 0 or > 20) return Fail("scroll-lines must be 0-20", 2);
                config = config with { ScrollLines = lines };
                break;
            case "dpi":
                if (!int.TryParse(value, out int dpi) || dpi is < 400 or > 4000) return Fail("dpi must be 400-4000", 2);
                config = config with { Dpi = dpi };
                break;
            default: return Fail($"unknown configuration key: {key}", 2);
        }
        store.Save(config);
        Console.WriteLine("ok");
        return 0;
    }

    private static string ParseAction(string value)
    {
        if (!Shortcut.TryParse(value, out Shortcut? shortcut)) throw new ArgumentException("invalid shortcut");
        return shortcut!.Canonical;
    }

    private static bool ParseBool(string value) => value.ToLowerInvariant() switch
    {
        "true" => true,
        "false" => false,
        _ => throw new ArgumentException("boolean value must be true or false"),
    };

    private static int Diagnose()
    {
        string version = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "unknown";
        RuntimeStatusSnapshot? runtime = RuntimeStatusStore.ReadLive();
        IReadOnlyList<HidInterfaceInfo> candidates = HidDeviceEnumerator.EnumerateM750();
        Console.WriteLine($"version={version}");
        Console.WriteLine($"os={RuntimeInformation.OSDescription}");
        Console.WriteLine($"architecture={RuntimeInformation.ProcessArchitecture}");
        Console.WriteLine($"config={AppPaths.ConfigPath}");
        Console.WriteLine($"log={DiagnosticLog.Shared.FilePath}");
        Console.WriteLine($"mouse-backend={(runtime?.MouseHookRunning == true ? "running" : "not-running")}");
        Console.WriteLine($"mappings-enabled={runtime?.MappingsEnabled.ToString().ToLowerInvariant() ?? "unknown"}");
        Console.WriteLine($"sendinput-failures={runtime?.InjectionFailures ?? 0}");
        Console.WriteLine($"m750-accessible-interfaces={candidates.Count}");
        Console.WriteLine($"hidpp-connected={runtime?.Hidpp.Connected.ToString().ToLowerInvariant() ?? "false"}");
        Console.WriteLine($"hidpp-report-lengths={(runtime?.Hidpp.Connected == true ? $"{runtime.Hidpp.InputReportLength}/{runtime.Hidpp.OutputReportLength}" : "unknown")}");
        Console.WriteLine($"dpi-source={(runtime?.Hidpp.Connected == true ? (runtime.Hidpp.DpisFromDevice ? "device" : "compatibility-fallback") : "unavailable")}");
        Console.WriteLine($"dpi-range={(runtime?.Hidpp.SupportedDpis.Count > 0 ? $"{runtime.Hidpp.SupportedDpis[0]}-{runtime.Hidpp.SupportedDpis[^1]} ({runtime.Hidpp.SupportedDpis.Count})" : "unavailable")}");
        Console.WriteLine($"dpi-current={runtime?.Hidpp.CurrentDpi?.ToString() ?? "unavailable"}");
        Console.WriteLine("uipi-note=SendInput cannot inject into applications running at a higher integrity level");
        return 0;
    }

    private static int Help(int code)
    {
        Console.WriteLine("""
            MouseBridge commands:
              MouseBridge config path
              MouseBridge config get
              MouseBridge config set middle|back|forward <shortcut|none>
              MouseBridge config set reverse-vertical|reverse-horizontal <true|false>
              MouseBridge config set scroll-lines <0-20>
              MouseBridge config set dpi <400-4000>
              MouseBridge diagnose
              MouseBridge --self-test
            """);
        return code;
    }

    private static int Fail(string message, int code)
    {
        Console.Error.WriteLine($"MouseBridge: {message}");
        return code;
    }
}
