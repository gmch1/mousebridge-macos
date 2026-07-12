// SPDX-License-Identifier: GPL-3.0-or-later

using System.Text.Json.Serialization;

namespace MouseBridge.Windows;

internal sealed record AppConfig
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; init; } = CurrentSchemaVersion;

    [JsonPropertyName("middleAction")]
    public string MiddleAction { get; init; } = string.Empty;

    [JsonPropertyName("backAction")]
    public string BackAction { get; init; } = "ctrl+r";

    [JsonPropertyName("forwardAction")]
    public string ForwardAction { get; init; } = "ctrl+w";

    [JsonPropertyName("reverseVerticalScroll")]
    public bool ReverseVerticalScroll { get; init; }

    [JsonPropertyName("reverseHorizontalScroll")]
    public bool ReverseHorizontalScroll { get; init; }

    [JsonPropertyName("scrollLines")]
    public int ScrollLines { get; init; }

    [JsonPropertyName("dpi")]
    public int Dpi { get; init; } = 1000;

    public AppConfig Normalize(IReadOnlyList<int>? supportedDpis = null)
    {
        int boundedDpi = Math.Clamp(Dpi, 400, 4000);
        if (supportedDpis is { Count: > 0 })
        {
            boundedDpi = supportedDpis
                .OrderBy(value => Math.Abs((long)value - boundedDpi))
                .ThenBy(value => value)
                .First();
        }

        return this with
        {
            SchemaVersion = CurrentSchemaVersion,
            MiddleAction = Shortcut.TryParse(MiddleAction, out Shortcut? middle) ? middle!.Canonical : MiddleAction.Trim().ToLowerInvariant(),
            BackAction = Shortcut.TryParse(BackAction, out Shortcut? back) ? back!.Canonical : BackAction.Trim().ToLowerInvariant(),
            ForwardAction = Shortcut.TryParse(ForwardAction, out Shortcut? forward) ? forward!.Canonical : ForwardAction.Trim().ToLowerInvariant(),
            ScrollLines = Math.Clamp(ScrollLines, 0, 20),
            Dpi = boundedDpi,
        };
    }

    public bool TryValidate(out string error)
    {
        if (SchemaVersion is < 1 or > CurrentSchemaVersion)
        {
            error = $"Unsupported schemaVersion {SchemaVersion}.";
            return false;
        }

        foreach ((string name, string? action) in new[]
                 {
                     ("middleAction", MiddleAction),
                     ("backAction", BackAction),
                     ("forwardAction", ForwardAction),
                 })
        {
            if (!Shortcut.TryParse(action, out _))
            {
                error = $"Invalid {name}.";
                return false;
            }
        }

        error = string.Empty;
        return true;
    }
}
