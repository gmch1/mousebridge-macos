// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

internal sealed class SettingsForm : Form
{
    private readonly ConfigStore _store;
    private readonly TextBox _middle = new();
    private readonly TextBox _back = new();
    private readonly TextBox _forward = new();
    private readonly CheckBox _reverseVertical = new() { Text = Strings.ReverseVertical, AutoSize = true };
    private readonly CheckBox _reverseHorizontal = new() { Text = Strings.ReverseHorizontal, AutoSize = true };
    private readonly TrackBar _scrollLines = new() { Minimum = 0, Maximum = 20, TickFrequency = 1, AutoSize = false, Height = 34 };
    private readonly TrackBar _dpi = new() { Minimum = 0, Maximum = 100, TickFrequency = 10, AutoSize = false, Height = 34 };
    private readonly Label _scrollValue = new() { AutoSize = true };
    private readonly Label _dpiValue = new() { AutoSize = true };
    private readonly Label _dpiRange = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    private readonly Label _deviceStatus = new() { AutoSize = true, Text = Strings.DeviceConnecting };
    private readonly Label _inputStatus = new() { AutoSize = true };
    private readonly Label _message = new() { AutoSize = true };
    private IReadOnlyList<int> _supportedDpis = Enumerable.Range(0, 37).Select(index => 400 + index * 100).ToArray();
    private bool _allowClose;

    public SettingsForm(ConfigStore store)
    {
        _store = store;
        Text = $"{Strings.ProductName} settings";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(620, 620);
        Size = new Size(720, 680);
        AutoScaleMode = AutoScaleMode.Dpi;
        BuildUi();
        LoadConfig(store.Current);
        if (store.LastError is not null)
        {
            _message.Text = $"Invalid configuration; using defaults: {store.LastError}";
            _message.ForeColor = Color.DarkRed;
        }
    }

    public void LoadConfig(AppConfig config)
    {
        _middle.Text = config.MiddleAction;
        _back.Text = config.BackAction;
        _forward.Text = config.ForwardAction;
        _reverseVertical.Checked = config.ReverseVerticalScroll;
        _reverseHorizontal.Checked = config.ReverseHorizontalScroll;
        _scrollLines.Value = Math.Clamp(config.ScrollLines, 0, 20);
        _dpi.Value = PercentForDpi(config.Dpi);
        UpdateValues();
    }

    public void SetInputStatus(bool running)
    {
        _inputStatus.Text = running ? Strings.HookRunning : Strings.HookStopped;
        _inputStatus.ForeColor = running ? Color.DarkGreen : Color.DarkOrange;
    }

    public void SetHidppStatus(HidppStatus status)
    {
        if (status.SupportedDpis.Count > 0) _supportedDpis = status.SupportedDpis;
        _deviceStatus.Text = status.Connected ? Strings.DeviceConnected : Strings.DeviceDisconnected;
        _deviceStatus.ForeColor = status.Connected ? Color.DarkGreen : Color.DarkOrange;
        string source = status.DpisFromDevice ? "device report" : "compatibility fallback";
        _dpiRange.Text = status.SupportedDpis.Count > 0
            ? $"{source}: {status.SupportedDpis[0]}–{status.SupportedDpis[^1]} DPI · {status.SupportedDpis.Count} values"
            : "DPI capabilities unavailable";
        _dpi.Value = PercentForDpi(_store.Current.Dpi);
        UpdateValues();
    }

    public void CloseForExit()
    {
        _allowClose = true;
        Close();
    }

    private void BuildUi()
    {
        TableLayoutPanel root = new()
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            Padding = new Padding(24),
            ColumnCount = 1,
            RowCount = 16,
        };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(root);

        Label title = new() { Text = Strings.ProductName, Font = new Font(Font.FontFamily, 20, FontStyle.Bold), AutoSize = true };
        Label preview = new() { Text = Strings.PreviewWarning, AutoSize = true, ForeColor = Color.DarkOrange };
        Label help = new() { Text = Strings.PassThroughHelp, AutoSize = true, ForeColor = SystemColors.GrayText };
        root.Controls.Add(title);
        root.Controls.Add(preview);
        root.Controls.Add(_deviceStatus);
        root.Controls.Add(_inputStatus);
        root.Controls.Add(help);
        root.Controls.Add(ActionGrid());
        root.Controls.Add(_reverseVertical);
        root.Controls.Add(_reverseHorizontal);
        root.Controls.Add(SliderRow(Strings.ScrollLines, _scrollLines, _scrollValue));
        root.Controls.Add(SliderRow(Strings.Dpi, _dpi, _dpiValue));
        root.Controls.Add(_dpiRange);
        root.Controls.Add(new Label
        {
            Text = "MouseBridge changes only mouse hook events. Touch/pen-originated wheel messages are passed through. Windows UIPI can block shortcuts sent to elevated applications.",
            AutoSize = true,
            MaximumSize = new Size(620, 0),
            ForeColor = SystemColors.GrayText,
        });
        root.Controls.Add(_message);
        Button save = new() { Text = Strings.SaveApply, AutoSize = true };
        save.Click += (_, _) => Save();
        root.Controls.Add(save);
        AcceptButton = save;

        _scrollLines.ValueChanged += (_, _) => UpdateValues();
        _dpi.ValueChanged += (_, _) => UpdateValues();
        FormClosing += (_, eventArgs) =>
        {
            if (_allowClose) return;
            eventArgs.Cancel = true;
            Hide();
        };
    }

    private Control ActionGrid()
    {
        TableLayoutPanel grid = new() { AutoSize = true, Dock = DockStyle.Top, ColumnCount = 2, RowCount = 3 };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        AddActionRow(grid, 0, Strings.MiddleButton, _middle);
        AddActionRow(grid, 1, Strings.BackButton, _back);
        AddActionRow(grid, 2, Strings.ForwardButton, _forward);
        return grid;
    }

    private static void AddActionRow(TableLayoutPanel grid, int row, string label, TextBox textBox)
    {
        textBox.Dock = DockStyle.Fill;
        grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        grid.Controls.Add(textBox, 1, row);
    }

    private static Control SliderRow(string title, TrackBar trackBar, Label value)
    {
        TableLayoutPanel row = new() { AutoSize = true, Dock = DockStyle.Top, ColumnCount = 3 };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145));
        trackBar.Dock = DockStyle.Fill;
        row.Controls.Add(new Label { Text = title, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        row.Controls.Add(trackBar, 1, 0);
        row.Controls.Add(value, 2, 0);
        return row;
    }

    private void Save()
    {
        if (!Shortcut.TryParse(_middle.Text, out Shortcut? middle) ||
            !Shortcut.TryParse(_back.Text, out Shortcut? back) ||
            !Shortcut.TryParse(_forward.Text, out Shortcut? forward))
        {
            _message.Text = Strings.InvalidShortcut;
            _message.ForeColor = Color.DarkRed;
            return;
        }
        try
        {
            AppConfig saved = _store.Save(_store.Current with
            {
                MiddleAction = middle!.Canonical,
                BackAction = back!.Canonical,
                ForwardAction = forward!.Canonical,
                ReverseVerticalScroll = _reverseVertical.Checked,
                ReverseHorizontalScroll = _reverseHorizontal.Checked,
                ScrollLines = _scrollLines.Value,
                Dpi = DpiForPercent(_dpi.Value),
            });
            LoadConfig(saved);
            _message.Text = Strings.Saved;
            _message.ForeColor = Color.DarkGreen;
        }
        catch (Exception exception)
        {
            _message.Text = exception.Message;
            _message.ForeColor = Color.DarkRed;
        }
    }

    private int DpiForPercent(int percent)
    {
        if (_supportedDpis.Count == 0) return 1000;
        int index = (int)Math.Round(percent / 100d * (_supportedDpis.Count - 1));
        return _supportedDpis[Math.Clamp(index, 0, _supportedDpis.Count - 1)];
    }

    private int PercentForDpi(int dpi)
    {
        if (_supportedDpis.Count <= 1) return 0;
        int index = Enumerable.Range(0, _supportedDpis.Count)
            .OrderBy(candidate => Math.Abs((long)_supportedDpis[candidate] - dpi))
            .First();
        return (int)Math.Round(index * 100d / (_supportedDpis.Count - 1));
    }

    private void UpdateValues()
    {
        _scrollValue.Text = _scrollLines.Value == 0 ? Strings.FollowDevice : $"{_scrollLines.Value} line(s)";
        _dpiValue.Text = $"{DpiForPercent(_dpi.Value)} DPI · {_dpi.Value}%";
    }
}
