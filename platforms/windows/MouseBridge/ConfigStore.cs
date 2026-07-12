// SPDX-License-Identifier: GPL-3.0-or-later

using System.Text.Json;
using System.Text.Json.Serialization;

namespace MouseBridge.Windows;

internal sealed class ConfigStore : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        AllowTrailingCommas = false,
        PropertyNameCaseInsensitive = false,
        ReadCommentHandling = JsonCommentHandling.Disallow,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        WriteIndented = true,
    };

    private readonly object _gate = new();
    private readonly DiagnosticLog _log;
    private FileSystemWatcher? _watcher;
    private System.Threading.Timer? _reloadTimer;
    private IReadOnlyList<int>? _supportedDpis;
    private bool _disposed;

    public ConfigStore(DiagnosticLog? log = null, string? configPath = null)
    {
        _log = log ?? DiagnosticLog.Shared;
        ConfigPath = configPath ?? AppPaths.ConfigPath;
        Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);

        if (File.Exists(ConfigPath))
        {
            if (TryRead(out AppConfig? loaded, out string error))
            {
                Current = loaded!;
            }
            else
            {
                Current = new AppConfig();
                LastError = error;
                _log.Write($"configuration initial load failed: {error}");
            }
        }
        else
        {
            Current = new AppConfig();
            Save(Current);
        }
    }

    public string ConfigPath { get; }
    public AppConfig Current { get; private set; }
    public string? LastError { get; private set; }
    public event EventHandler<AppConfig>? Changed;

    public void StartWatching()
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_watcher is not null) return;
            _watcher = new FileSystemWatcher(Path.GetDirectoryName(ConfigPath)!, Path.GetFileName(ConfigPath))
            {
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime,
            };
            _watcher.Changed += ScheduleReload;
            _watcher.Created += ScheduleReload;
            _watcher.Deleted += ScheduleReload;
            _watcher.Renamed += ScheduleReload;
            _watcher.Error += (_, eventArgs) => _log.Write($"configuration watcher error: {eventArgs.GetException().Message}");
            _watcher.EnableRaisingEvents = true;
        }
    }

    public AppConfig Save(AppConfig proposed)
    {
        if (!proposed.TryValidate(out string validationError))
        {
            throw new ArgumentException(validationError, nameof(proposed));
        }

        AppConfig normalized;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            normalized = proposed.Normalize(_supportedDpis);
            WriteAtomic(normalized);
            LastError = null;
            if (normalized == Current) return normalized;
            Current = normalized;
        }

        Changed?.Invoke(this, normalized);
        return normalized;
    }

    public void SetSupportedDpis(IReadOnlyList<int> values)
    {
        int[] normalizedValues = values.Where(value => value is >= 100 and <= 10000).Distinct().Order().ToArray();
        if (normalizedValues.Length == 0) return;
        AppConfig snapshot;
        lock (_gate)
        {
            _supportedDpis = normalizedValues;
            snapshot = Current;
        }
        if (snapshot.Normalize(normalizedValues) != snapshot) Save(snapshot);
    }

    private void ScheduleReload(object? sender, FileSystemEventArgs eventArgs)
    {
        lock (_gate)
        {
            if (_disposed) return;
            _reloadTimer ??= new System.Threading.Timer(_ => ReloadFromDisk(), null, Timeout.Infinite, Timeout.Infinite);
            _reloadTimer.Change(175, Timeout.Infinite);
        }
    }

    private void ReloadFromDisk()
    {
        if (!File.Exists(ConfigPath))
        {
            RecordReloadError("configuration file was removed; keeping the last valid configuration");
            return;
        }

        if (!TryRead(out AppConfig? loaded, out string error))
        {
            RecordReloadError(error);
            return;
        }

        bool changed;
        lock (_gate)
        {
            if (_disposed) return;
            LastError = null;
            changed = loaded != Current;
            if (changed) Current = loaded!;
        }
        if (changed)
        {
            _log.Write("configuration reloaded from disk");
            Changed?.Invoke(this, loaded!);
        }
    }

    private void RecordReloadError(string error)
    {
        lock (_gate)
        {
            if (_disposed) return;
            LastError = error;
        }
        _log.Write($"configuration reload failed: {error}");
    }

    private bool TryRead(out AppConfig? config, out string error)
    {
        try
        {
            using FileStream stream = new(ConfigPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            AppConfig? decoded = JsonSerializer.Deserialize<AppConfig>(stream, JsonOptions);
            if (decoded is null)
            {
                config = null;
                error = "configuration is empty";
                return false;
            }
            if (!decoded.TryValidate(out error))
            {
                config = null;
                return false;
            }
            lock (_gate) config = decoded.Normalize(_supportedDpis);
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            config = null;
            error = exception.Message;
            return false;
        }
    }

    private void WriteAtomic(AppConfig config)
    {
        string directory = Path.GetDirectoryName(ConfigPath)!;
        Directory.CreateDirectory(directory);
        string temporaryPath = Path.Combine(directory, $".{Path.GetFileName(ConfigPath)}.{Environment.ProcessId}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (FileStream stream = new(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, config, JsonOptions);
                stream.WriteByte((byte)'\n');
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporaryPath, ConfigPath, overwrite: true);
        }
        finally
        {
            try { File.Delete(temporaryPath); } catch { }
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _watcher?.Dispose();
            _watcher = null;
            _reloadTimer?.Dispose();
            _reloadTimer = null;
        }
    }
}
