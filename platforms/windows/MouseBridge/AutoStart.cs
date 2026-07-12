// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

// Kept behind an interface so a later signed build can choose a Startup Task
// or per-user Run-key implementation without coupling it to the tray lifecycle.
internal interface IAutoStartController
{
    bool IsAvailable { get; }
    bool IsEnabled { get; }
    void SetEnabled(bool enabled);
}

internal sealed class PreviewAutoStartController : IAutoStartController
{
    public bool IsAvailable => false;
    public bool IsEnabled => false;
    public void SetEnabled(bool enabled) => throw new NotSupportedException("Auto-start is not available in 0.1.0-preview.");
}
