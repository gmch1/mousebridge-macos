// SPDX-License-Identifier: GPL-3.0-or-later

using System.Text;

namespace MouseBridge.Windows;

internal sealed class DiagnosticLog
{
    private readonly object _gate = new();
    public static DiagnosticLog Shared { get; } = new();
    public string FilePath { get; } = Path.Combine(AppPaths.DirectoryPath, "MouseBridge.log");

    public void Write(string message)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DirectoryPath);
            string clean = message.Replace('\r', ' ').Replace('\n', ' ');
            string line = $"{DateTimeOffset.Now:O} {clean}{Environment.NewLine}";
            lock (_gate)
            {
                File.AppendAllText(FilePath, line, new UTF8Encoding(false));
            }
        }
        catch
        {
            // Diagnostics must never take down input handling or the tray app.
        }
    }
}

internal static class AppPaths
{
    public static string DirectoryPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "MouseBridge");
    public static string ConfigPath { get; } = Path.Combine(DirectoryPath, "config.json");
}
