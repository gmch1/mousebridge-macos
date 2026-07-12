// SPDX-License-Identifier: GPL-3.0-or-later

using System.Text.Json;

namespace MouseBridge.Windows;

internal sealed record RuntimeStatusSnapshot(
    int ProcessId,
    bool MouseHookRunning,
    bool MappingsEnabled,
    long InjectionFailures,
    HidppStatus Hidpp,
    DateTimeOffset UpdatedAt);

internal static class RuntimeStatusStore
{
    public static string FilePath { get; } = Path.Combine(AppPaths.DirectoryPath, "runtime-status.json");

    public static void Write(RuntimeStatusSnapshot status)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DirectoryPath);
            string temporary = FilePath + $".{Environment.ProcessId}.tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(status, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, FilePath, true);
        }
        catch (Exception exception)
        {
            DiagnosticLog.Shared.Write($"runtime status write failed: {exception.GetType().Name}");
        }
    }

    public static RuntimeStatusSnapshot? ReadLive()
    {
        try
        {
            RuntimeStatusSnapshot? status = JsonSerializer.Deserialize<RuntimeStatusSnapshot>(File.ReadAllText(FilePath));
            if (status is null) return null;
            using System.Diagnostics.Process process = System.Diagnostics.Process.GetProcessById(status.ProcessId);
            return process.HasExited ? null : status;
        }
        catch { return null; }
    }

    public static void Delete()
    {
        try { File.Delete(FilePath); } catch { }
    }
}
