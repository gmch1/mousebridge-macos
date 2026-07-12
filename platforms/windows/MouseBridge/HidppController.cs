// SPDX-License-Identifier: GPL-3.0-or-later

using System.Runtime.InteropServices;

namespace MouseBridge.Windows;

internal sealed record HidppStatus(
    bool Connected,
    bool BackendRunning,
    ushort UsagePage,
    ushort Usage,
    int InputReportLength,
    int OutputReportLength,
    IReadOnlyList<int> SupportedDpis,
    bool DpisFromDevice,
    int? CurrentDpi,
    string? LastError)
{
    public static HidppStatus Stopped { get; } = new(false, false, 0, 0, 0, 0, [], false, null, null);
}

internal sealed class HidppController : IAsyncDisposable
{
    private readonly object _stateGate = new();
    private readonly Func<int> _desiredDpi;
    private readonly DiagnosticLog _log;
    private readonly CancellationTokenSource _stop = new();
    private Task? _worker;
    private HidppSession? _session;
    private byte _dpiFeature;
    private int? _originalDpi;
    private HidppStatus _status = HidppStatus.Stopped;

    public HidppController(Func<int> desiredDpi, DiagnosticLog? log = null)
    {
        _desiredDpi = desiredDpi;
        _log = log ?? DiagnosticLog.Shared;
    }

    public event EventHandler<HidppStatus>? StatusChanged;

    public HidppStatus Status
    {
        get { lock (_stateGate) return _status; }
    }

    public void Start()
    {
        lock (_stateGate)
        {
            if (_worker is not null) return;
            _status = _status with { BackendRunning = true, LastError = null };
            _worker = Task.Run(() => WorkerAsync(_stop.Token));
        }
        PublishStatus();
    }

    public async Task<bool> SetDpiAsync(int requested, CancellationToken cancellationToken = default)
    {
        HidppSession? session;
        byte feature;
        IReadOnlyList<int> supported;
        lock (_stateGate)
        {
            session = _session;
            feature = _dpiFeature;
            supported = _status.SupportedDpis;
        }
        if (session is null || feature == 0) return false;
        int bounded = Math.Clamp(requested, 400, 4000);
        int dpi = supported.Count > 0
            ? supported.OrderBy(value => Math.Abs((long)value - bounded)).ThenBy(value => value).First()
            : bounded;
        HidppMessage? response = await session.RequestAsync(
            feature,
            3,
            [0, (byte)(dpi >> 8), (byte)dpi],
            cancellationToken).ConfigureAwait(false);
        if (response is null) return false;
        UpdateStatus(status => status with { CurrentDpi = dpi, LastError = null });
        return true;
    }

    private async Task WorkerAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            bool connected = false;
            try
            {
                IReadOnlyList<HidInterfaceInfo> candidates = HidDeviceEnumerator.EnumerateM750(_log);
                if (candidates.Count == 0)
                {
                    UpdateStatus(status => status with { Connected = false, LastError = "No readable/writeable VID_046D&PID_B02C HID interface was found." });
                }
                foreach (HidInterfaceInfo candidate in candidates)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (await TryRunCandidateAsync(candidate, cancellationToken).ConfigureAwait(false))
                    {
                        connected = true;
                        break;
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                _log.Write($"HID++ worker failed: {exception.GetType().Name}: {exception.Message}");
                UpdateStatus(status => status with { Connected = false, LastError = exception.Message });
            }

            if (cancellationToken.IsCancellationRequested) break;
            if (!connected) UpdateStatus(status => status with { Connected = false });
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
        }
    }

    private async Task<bool> TryRunCandidateAsync(HidInterfaceInfo candidate, CancellationToken cancellationToken)
    {
        if (candidate.InputReportLength < 7 || candidate.OutputReportLength < HidppProtocol.FrameLength)
        {
            _log.Write($"HID++ candidate rejected for report lengths input={candidate.InputReportLength} output={candidate.OutputReportLength}");
            return false;
        }

        Microsoft.Win32.SafeHandles.SafeFileHandle handle = NativeMethods.CreateFileW(
            candidate.Path,
            NativeMethods.GenericRead | NativeMethods.GenericWrite,
            NativeMethods.FileShareRead | NativeMethods.FileShareWrite,
            0,
            NativeMethods.OpenExisting,
            NativeMethods.FileFlagOverlapped,
            0);
        if (handle.IsInvalid)
        {
            handle.Dispose();
            _log.Write($"HID++ candidate reopen failed error={Marshal.GetLastWin32Error()}");
            return false;
        }

        await using HidppSession session = new(handle, candidate.InputReportLength, candidate.OutputReportLength, _log);
        session.Start();
        HidppMessage? root = await session.RequestAsync(
            0,
            0,
            [(byte)(HidppProtocol.AdjustableDpiFeature >> 8), (byte)(HidppProtocol.AdjustableDpiFeature & 0xFF), 0],
            cancellationToken).ConfigureAwait(false);
        byte feature = root?.Parameters.FirstOrDefault() ?? 0;
        if (feature == 0)
        {
            _log.Write("HID interface rejected: Adjustable DPI feature 0x2201 not reported");
            return false;
        }

        IReadOnlyList<int> dpis = await ReadSupportedDpisAsync(session, feature, cancellationToken).ConfigureAwait(false);
        bool fromDevice = dpis.Count > 0;
        if (!fromDevice)
        {
            // Compatibility fallback is surfaced explicitly and is not used to identify the interface.
            dpis = Enumerable.Range(0, 37).Select(index => 400 + index * 100).ToArray();
        }
        int? current = await ReadDpiAsync(session, feature, cancellationToken).ConfigureAwait(false);

        lock (_stateGate)
        {
            _session = session;
            _dpiFeature = feature;
            _originalDpi = current;
            _status = new HidppStatus(
                true,
                true,
                candidate.UsagePage,
                candidate.Usage,
                candidate.InputReportLength,
                candidate.OutputReportLength,
                dpis,
                fromDevice,
                current,
                null);
        }
        _log.Write($"HID++ connected feature={feature:X2} dpiCount={dpis.Count} fromDevice={fromDevice} current={current?.ToString() ?? "unknown"}");
        PublishStatus();
        _ = await SetDpiAsync(_desiredDpi(), cancellationToken).ConfigureAwait(false);

        try
        {
            await session.Disconnected.WaitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        finally
        {
            lock (_stateGate)
            {
                if (ReferenceEquals(_session, session))
                {
                    _session = null;
                    _dpiFeature = 0;
                    _originalDpi = null;
                    _status = _status with { Connected = false, CurrentDpi = null, LastError = cancellationToken.IsCancellationRequested ? null : "Device disconnected." };
                }
            }
            PublishStatus();
        }
        return true;
    }

    private static async Task<IReadOnlyList<int>> ReadSupportedDpisAsync(HidppSession session, byte feature, CancellationToken cancellationToken)
    {
        List<byte> bytes = [];
        for (byte page = 0; page < 16; page++)
        {
            HidppMessage? response = await session.RequestAsync(feature, 1, [0, 0, page], cancellationToken).ConfigureAwait(false);
            if (response is null || response.Value.Parameters.Length <= 1) break;
            byte[] payload = response.Value.Parameters[1..];
            bytes.AddRange(payload);
            bool terminated = false;
            for (int index = 0; index + 1 < payload.Length; index += 2)
            {
                if (payload[index] == 0 && payload[index + 1] == 0) { terminated = true; break; }
            }
            if (terminated) break;
        }
        return HidppProtocol.DecodeDpiList(bytes.ToArray());
    }

    private static async Task<int?> ReadDpiAsync(HidppSession session, byte feature, CancellationToken cancellationToken)
    {
        HidppMessage? response = await session.RequestAsync(feature, 2, [0], cancellationToken).ConfigureAwait(false);
        if (response is null || response.Value.Parameters.Length < 3) return null;
        byte[] parameters = response.Value.Parameters;
        int current = (parameters[1] << 8) | parameters[2];
        if (current != 0) return current;
        return parameters.Length >= 5 ? (parameters[3] << 8) | parameters[4] : null;
    }

    private void UpdateStatus(Func<HidppStatus, HidppStatus> update)
    {
        lock (_stateGate) _status = update(_status);
        PublishStatus();
    }

    private void PublishStatus() => StatusChanged?.Invoke(this, Status);

    public async ValueTask DisposeAsync()
    {
        HidppSession? session;
        byte feature;
        int? original;
        lock (_stateGate)
        {
            session = _session;
            feature = _dpiFeature;
            original = _originalDpi;
        }
        if (session is not null && feature != 0 && original is not null)
        {
            try
            {
                using CancellationTokenSource restoreTimeout = new(TimeSpan.FromMilliseconds(1800));
                HidppMessage? response = await session.RequestAsync(
                    feature,
                    3,
                    [0, (byte)(original.Value >> 8), (byte)original.Value],
                    restoreTimeout.Token).ConfigureAwait(false);
                _log.Write($"DPI restore value={original} success={response is not null}");
            }
            catch (Exception exception)
            {
                _log.Write($"DPI restore failed: {exception.GetType().Name}");
            }
        }

        _stop.Cancel();
        session?.Abort();
        Task? worker;
        lock (_stateGate) worker = _worker;
        if (worker is not null)
        {
            try { await worker.WaitAsync(TimeSpan.FromSeconds(3)).ConfigureAwait(false); } catch { }
        }
        _stop.Dispose();
        UpdateStatus(status => status with { Connected = false, BackendRunning = false });
    }
}

internal sealed class HidppSession : IAsyncDisposable
{
    private sealed record Pending(byte Feature, byte Function, TaskCompletionSource<HidppMessage?> Completion);

    private readonly FileStream _stream;
    private readonly int _inputReportLength;
    private readonly int _outputReportLength;
    private readonly DiagnosticLog _log;
    private readonly CancellationTokenSource _abort = new();
    private readonly SemaphoreSlim _requestGate = new(1, 1);
    private readonly object _pendingGate = new();
    private readonly TaskCompletionSource _disconnected = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Pending? _pending;
    private Task? _reader;

    public HidppSession(Microsoft.Win32.SafeHandles.SafeFileHandle handle, int inputReportLength, int outputReportLength, DiagnosticLog log)
    {
        _stream = new FileStream(handle, FileAccess.ReadWrite, Math.Max(inputReportLength, 64), isAsync: true);
        _inputReportLength = inputReportLength;
        _outputReportLength = outputReportLength;
        _log = log;
    }

    public Task Disconnected => _disconnected.Task;

    public void Start() => _reader ??= Task.Run(() => ReadLoopAsync(_abort.Token));

    public async Task<HidppMessage?> RequestAsync(byte feature, byte function, byte[] parameters, CancellationToken cancellationToken)
    {
        await _requestGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            TaskCompletionSource<HidppMessage?> completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            Pending pending = new(feature, function, completion);
            lock (_pendingGate) _pending = pending;
            try
            {
                byte[] frame = HidppProtocol.BuildRequest(feature, function, parameters, _outputReportLength);
                using CancellationTokenSource timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _abort.Token);
                timeout.CancelAfter(TimeSpan.FromMilliseconds(1800));
                await _stream.WriteAsync(frame, timeout.Token).ConfigureAwait(false);
                HidppMessage? response = await completion.Task.WaitAsync(timeout.Token).ConfigureAwait(false);
                if (response is { IsError: true } error)
                {
                    _log.Write($"HID++ error feature={feature:X2} function={function} code={error.ErrorCode:X2}");
                    return null;
                }
                return response;
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested && !_abort.IsCancellationRequested)
            {
                _log.Write($"HID++ request timeout feature={feature:X2} function={function}");
                return null;
            }
            catch (Exception exception) when (exception is IOException or ObjectDisposedException or OperationCanceledException)
            {
                if (!cancellationToken.IsCancellationRequested)
                    _log.Write($"HID++ request failed feature={feature:X2} function={function} type={exception.GetType().Name}");
                return null;
            }
            finally
            {
                lock (_pendingGate) if (ReferenceEquals(_pending, pending)) _pending = null;
            }
        }
        finally
        {
            _requestGate.Release();
        }
    }

    private async Task ReadLoopAsync(CancellationToken cancellationToken)
    {
        byte[] buffer = new byte[_inputReportLength];
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                int count = await _stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
                if (count == 0) break;
                if (!HidppProtocol.TryParse(buffer.AsSpan(0, count), out HidppMessage message)) continue;
                Pending? pending;
                lock (_pendingGate) pending = _pending;
                if (pending is not null &&
                    message.FeatureIndex == pending.Feature &&
                    message.Function == pending.Function &&
                    message.SoftwareId == HidppProtocol.SoftwareId)
                {
                    pending.Completion.TrySetResult(message);
                }
            }
        }
        catch (Exception exception) when (exception is IOException or ObjectDisposedException or OperationCanceledException)
        {
            if (!cancellationToken.IsCancellationRequested) _log.Write($"HID++ read loop ended: {exception.GetType().Name}");
        }
        finally
        {
            Pending? pending;
            lock (_pendingGate) { pending = _pending; _pending = null; }
            pending?.Completion.TrySetResult(null);
            _disconnected.TrySetResult();
        }
    }

    public void Abort()
    {
        if (_abort.IsCancellationRequested) return;
        _abort.Cancel();
        _stream.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        Abort();
        if (_reader is not null)
        {
            try { await _reader.ConfigureAwait(false); } catch { }
        }
        _requestGate.Dispose();
        _abort.Dispose();
    }
}
