// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

internal sealed class MouseBridgeContext : ApplicationContext
{
    private readonly ConfigStore _config = new();
    private readonly SettingsForm _settings;
    private readonly NotifyIcon _tray;
    private readonly ToolStripMenuItem _toggle;
    private readonly ToolStripMenuItem _inputStatus;
    private readonly ToolStripMenuItem _deviceStatus;
    private readonly MouseHook _hook;
    private readonly HidppController _hidpp;
    private readonly EventWaitHandle _showSettingsEvent;
    private readonly CancellationTokenSource _showWaitStop = new();
    private readonly System.Windows.Forms.Timer _runtimeStatusTimer = new() { Interval = 2000 };
    private bool _mappingsEnabled = true;
    private bool _exiting;

    public MouseBridgeContext(EventWaitHandle showSettingsEvent)
    {
        _showSettingsEvent = showSettingsEvent;
        _settings = new SettingsForm(_config);
        _ = _settings.Handle;
        _hook = new MouseHook(() => _config.Current, () => _mappingsEnabled);
        _hidpp = new HidppController(() => _config.Current.Dpi);
        _deviceStatus = new ToolStripMenuItem(Strings.DeviceConnecting) { Enabled = false };
        _inputStatus = new ToolStripMenuItem(Strings.HookStopped) { Enabled = false };
        _toggle = new ToolStripMenuItem(Strings.PauseMappings, null, (_, _) => ToggleMappings());
        ContextMenuStrip menu = BuildMenu();
        _tray = new NotifyIcon
        {
            Text = Strings.ProductName,
            Icon = SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => ShowSettings();

        _config.Changed += ConfigChanged;
        _config.StartWatching();
        bool hookStarted = _hook.Start();
        _settings.SetInputStatus(hookStarted);
        _inputStatus.Text = hookStarted ? Strings.HookRunning : Strings.HookStopped;
        _hidpp.StatusChanged += HidppStatusChanged;
        _hidpp.Start();
        _runtimeStatusTimer.Tick += (_, _) => WriteRuntimeStatus();
        _runtimeStatusTimer.Start();
        WriteRuntimeStatus();
        _ = Task.Run(() => WaitForShowRequest(_showWaitStop.Token));
        ShowSettings();
    }

    private ContextMenuStrip BuildMenu()
    {
        ContextMenuStrip menu = new();
        menu.Items.Add(_deviceStatus);
        menu.Items.Add(_inputStatus);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Strings.OpenSettings, null, (_, _) => ShowSettings());
        menu.Items.Add(_toggle);
        menu.Items.Add(Strings.Diagnostics, null, (_, _) => ShowDiagnostics());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Strings.About, null, (_, _) => ShowAbout());
        menu.Items.Add(Strings.Exit, null, (_, _) => Shutdown());
        return menu;
    }

    private void ConfigChanged(object? sender, AppConfig config)
    {
        SafeBeginInvoke(async () =>
        {
            _settings.LoadConfig(config);
            try { _ = await _hidpp.SetDpiAsync(config.Dpi); } catch { }
            WriteRuntimeStatus();
        });
    }

    private void HidppStatusChanged(object? sender, HidppStatus status)
    {
        SafeBeginInvoke(() =>
        {
            _settings.SetHidppStatus(status);
            _deviceStatus.Text = status.Connected ? Strings.DeviceConnected : Strings.DeviceDisconnected;
            if (status.SupportedDpis.Count > 0) _config.SetSupportedDpis(status.SupportedDpis);
            WriteRuntimeStatus();
        });
    }

    private void ToggleMappings()
    {
        _mappingsEnabled = !_mappingsEnabled;
        _toggle.Text = _mappingsEnabled ? Strings.PauseMappings : Strings.ResumeMappings;
        WriteRuntimeStatus();
    }

    private void ShowSettings()
    {
        if (_settings.WindowState == FormWindowState.Minimized) _settings.WindowState = FormWindowState.Normal;
        _settings.Show();
        _settings.Activate();
    }

    private void ShowDiagnostics()
    {
        HidppStatus status = _hidpp.Status;
        string dpi = status.SupportedDpis.Count > 0
            ? $"{status.SupportedDpis[0]}–{status.SupportedDpis[^1]} ({status.SupportedDpis.Count}); current {status.CurrentDpi?.ToString() ?? "unknown"}"
            : "unavailable";
        MessageBox.Show(
            $"Mouse hook: {(_hook.IsRunning ? "running" : "not running")}\n" +
            $"Mappings: {(_mappingsEnabled ? "enabled" : "paused")}\n" +
            $"HID++: {(status.Connected ? "connected" : "not connected")}\n" +
            $"DPI: {dpi}\n" +
            $"Config: {_config.ConfigPath}\n" +
            $"Log: {DiagnosticLog.Shared.FilePath}\n\n" +
            "Windows UIPI prevents SendInput from targeting applications running at a higher integrity level.",
            Strings.Diagnostics,
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private static void ShowAbout()
    {
        MessageBox.Show(
            "MouseBridge 0.1.0-preview\n\n" +
            "Copyright © 2026 guomingchao and MouseBridge contributors.\n\n" +
            "Free software under GPL-3.0-or-later, without warranty. You may copy, modify, and redistribute it under the license. " +
            "The complete license, third-party notices, and corresponding-source information are included in the distribution.\n\n" +
            "Source: https://github.com/gmch1/mousebridge-macos",
            Strings.About,
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private void WriteRuntimeStatus() => RuntimeStatusStore.Write(new RuntimeStatusSnapshot(
        Environment.ProcessId,
        _hook.IsRunning,
        _mappingsEnabled,
        _hook.InjectionFailures,
        _hidpp.Status,
        DateTimeOffset.UtcNow));

    private void WaitForShowRequest(CancellationToken cancellationToken)
    {
        WaitHandle[] handles = [_showSettingsEvent, cancellationToken.WaitHandle];
        while (!cancellationToken.IsCancellationRequested)
        {
            if (WaitHandle.WaitAny(handles) != 0) return;
            SafeBeginInvoke(ShowSettings);
        }
    }

    private void SafeBeginInvoke(Action action)
    {
        if (_exiting || _settings.IsDisposed) return;
        try { _settings.BeginInvoke(action); } catch (InvalidOperationException) { }
    }

    private void Shutdown()
    {
        if (_exiting) return;
        _exiting = true;
        _runtimeStatusTimer.Stop();
        _showWaitStop.Cancel();
        _config.Changed -= ConfigChanged;
        _config.Dispose();
        _hook.Dispose();
        try { _hidpp.DisposeAsync().AsTask().GetAwaiter().GetResult(); } catch { }
        _tray.Visible = false;
        _tray.Dispose();
        RuntimeStatusStore.Delete();
        _settings.CloseForExit();
        _showWaitStop.Dispose();
        ExitThread();
    }

    protected override void ExitThreadCore()
    {
        if (!_exiting) Shutdown();
        else base.ExitThreadCore();
    }
}
