// SPDX-License-Identifier: GPL-3.0-or-later

using System.Runtime.InteropServices;

namespace MouseBridge.Windows;

internal sealed class MouseHook : IDisposable
{
    internal const nuint InjectionMarker = 0x4D425249; // "MBRI"
    private readonly Func<AppConfig> _configProvider;
    private readonly Func<bool> _enabledProvider;
    private readonly DiagnosticLog _log;
    private readonly NativeMethods.LowLevelMouseProc _callback;
    private nint _hook;
    private bool _middleConsumed;
    private bool _backConsumed;
    private bool _forwardConsumed;
    private long _injectionFailures;
    private int _systemLinesPerDetent = 1;

    public MouseHook(Func<AppConfig> configProvider, Func<bool> enabledProvider, DiagnosticLog? log = null)
    {
        _configProvider = configProvider;
        _enabledProvider = enabledProvider;
        _log = log ?? DiagnosticLog.Shared;
        _callback = HookCallback;
    }

    public bool IsRunning => _hook != 0;
    public long InjectionFailures => Interlocked.Read(ref _injectionFailures);

    public bool Start()
    {
        if (_hook != 0) return true;
        if (NativeMethods.SystemParametersInfoW(NativeMethods.SpiGetWheelScrollLines, 0, out uint lines, 0) && lines is > 0 and < 100)
            _systemLinesPerDetent = (int)lines;
        nint module = NativeMethods.GetModuleHandleW(null);
        _hook = NativeMethods.SetWindowsHookExW(NativeMethods.WhMouseLl, _callback, module, 0);
        if (_hook == 0)
        {
            _log.Write($"mouse hook start failed: {Marshal.GetLastWin32Error()}");
            return false;
        }
        _log.Write("mouse hook started");
        return true;
    }

    private nint HookCallback(int code, nuint message, nint data)
    {
        if (code < 0) return NativeMethods.CallNextHookEx(_hook, code, message, data);
        try
        {
            NativeMethods.MsllHookStruct mouse = Marshal.PtrToStructure<NativeMethods.MsllHookStruct>(data);
            if (ShouldIgnore(mouse.Flags, mouse.ExtraInfo))
            {
                return NativeMethods.CallNextHookEx(_hook, code, message, data);
            }

            uint kind = unchecked((uint)message);
            if (kind is NativeMethods.WmMouseWheel or NativeMethods.WmMouseHWheel)
            {
                if (!_enabledProvider() || !IsPhysicalMouseMessage(mouse.ExtraInfo))
                    return NativeMethods.CallNextHookEx(_hook, code, message, data);
                return HandleWheel(code, message, data, kind, mouse);
            }

            return kind switch
            {
                NativeMethods.WmMButtonDown => HandleButtonDown(MouseButton.Middle, code, message, data),
                NativeMethods.WmMButtonUp => HandleButtonUp(MouseButton.Middle, code, message, data),
                NativeMethods.WmXButtonDown => HandleButtonDown(XButton(mouse.MouseData), code, message, data),
                NativeMethods.WmXButtonUp => HandleButtonUp(XButton(mouse.MouseData), code, message, data),
                _ => NativeMethods.CallNextHookEx(_hook, code, message, data),
            };
        }
        catch (Exception exception)
        {
            _log.Write($"mouse hook callback failed: {exception.GetType().Name}");
            return NativeMethods.CallNextHookEx(_hook, code, message, data);
        }
    }

    internal static bool ShouldIgnore(uint flags, nuint extraInfo) =>
        (flags & (NativeMethods.LlMouseInjected | NativeMethods.LlMouseLowerIlInjected)) != 0 || extraInfo == InjectionMarker;

    private bool IsPhysicalMouseMessage(nuint extraInfo)
    {
        // Touch-generated legacy mouse messages use the documented MI_WP_SIGNATURE.
        if ((((ulong)extraInfo) & 0xFFFFFF00UL) == 0xFF515700UL) return false;
        if (!NativeMethods.GetCurrentInputMessageSource(out NativeMethods.InputMessageSource source)) return true;
        return source.DeviceType is not (NativeMethods.InputMessageDeviceType.Touch or NativeMethods.InputMessageDeviceType.Pen);
    }

    private nint HandleWheel(int code, nuint message, nint data, uint kind, NativeMethods.MsllHookStruct mouse)
    {
        int delta = unchecked((short)(mouse.MouseData >> 16));
        AppConfig config = _configProvider();
        bool horizontal = kind == NativeMethods.WmMouseHWheel;
        int? transformed = horizontal
            ? ScrollTransform.Transform(delta, config.ReverseHorizontalScroll, 0)
            : ScrollTransform.Transform(delta, config.ReverseVerticalScroll, config.ScrollLines, _systemLinesPerDetent);
        if (transformed is null || transformed == delta)
            return NativeMethods.CallNextHookEx(_hook, code, message, data);

        NativeMethods.Input input = new()
        {
            Type = NativeMethods.InputMouse,
            Data = new NativeMethods.InputUnion
            {
                Mouse = new NativeMethods.MouseInput
                {
                    MouseData = unchecked((uint)transformed.Value),
                    Flags = horizontal ? NativeMethods.MouseEventHWheel : NativeMethods.MouseEventWheel,
                    ExtraInfo = InjectionMarker,
                },
            },
        };
        if (NativeMethods.SendInput(1, [input], Marshal.SizeOf<NativeMethods.Input>()) == 1) return 1;
        RecordInjectionFailure("wheel");
        return NativeMethods.CallNextHookEx(_hook, code, message, data);
    }

    private nint HandleButtonDown(MouseButton button, int code, nuint message, nint data)
    {
        if (button == MouseButton.Unknown) return NativeMethods.CallNextHookEx(_hook, code, message, data);
        if (GetConsumed(button)) return 1;
        if (!_enabledProvider()) return NativeMethods.CallNextHookEx(_hook, code, message, data);
        string action = button switch
        {
            MouseButton.Middle => _configProvider().MiddleAction,
            MouseButton.Back => _configProvider().BackAction,
            MouseButton.Forward => _configProvider().ForwardAction,
            _ => string.Empty,
        };
        if (!Shortcut.TryParse(action, out Shortcut? shortcut) || shortcut!.IsPassThrough)
            return NativeMethods.CallNextHookEx(_hook, code, message, data);

        SetConsumed(button, true);
        if (!shortcut.IsNone && !SendShortcut(shortcut)) RecordInjectionFailure("keyboard/UIPI");
        return 1;
    }

    private nint HandleButtonUp(MouseButton button, int code, nuint message, nint data)
    {
        if (button != MouseButton.Unknown && GetConsumed(button))
        {
            SetConsumed(button, false);
            return 1;
        }
        return NativeMethods.CallNextHookEx(_hook, code, message, data);
    }

    private static MouseButton XButton(uint data) => (data >> 16) switch
    {
        NativeMethods.XButton1 => MouseButton.Back,
        NativeMethods.XButton2 => MouseButton.Forward,
        _ => MouseButton.Unknown,
    };

    private bool SendShortcut(Shortcut shortcut)
    {
        List<ushort> modifierKeys = [];
        if (shortcut.Modifiers.HasFlag(ShortcutModifiers.Control)) modifierKeys.Add(0x11);
        if (shortcut.Modifiers.HasFlag(ShortcutModifiers.Shift)) modifierKeys.Add(0x10);
        if (shortcut.Modifiers.HasFlag(ShortcutModifiers.Alt)) modifierKeys.Add(0x12);
        if (shortcut.Modifiers.HasFlag(ShortcutModifiers.Meta)) modifierKeys.Add(0x5B);
        List<NativeMethods.Input> events = [];
        events.AddRange(modifierKeys.Select(key => KeyInput(key, keyUp: false)));
        events.Add(KeyInput(shortcut.VirtualKey, keyUp: false));
        events.Add(KeyInput(shortcut.VirtualKey, keyUp: true));
        events.AddRange(modifierKeys.AsEnumerable().Reverse().Select(key => KeyInput(key, keyUp: true)));
        uint sent = NativeMethods.SendInput((uint)events.Count, events.ToArray(), Marshal.SizeOf<NativeMethods.Input>());
        if (sent == events.Count) return true;

        // Best effort: a partially accepted SendInput sequence must not leave modifiers held.
        NativeMethods.Input[] releases = modifierKeys
            .Append(shortcut.VirtualKey)
            .Reverse()
            .Select(key => KeyInput(key, keyUp: true))
            .ToArray();
        _ = NativeMethods.SendInput((uint)releases.Length, releases, Marshal.SizeOf<NativeMethods.Input>());
        return false;
    }

    private static NativeMethods.Input KeyInput(ushort key, bool keyUp)
    {
        bool extended = key is >= 0x21 and <= 0x2E or 0x5B or 0x5C;
        uint flags = (keyUp ? NativeMethods.KeyEventKeyUp : 0) | (extended ? NativeMethods.KeyEventExtendedKey : 0);
        return new NativeMethods.Input
        {
            Type = NativeMethods.InputKeyboard,
            Data = new NativeMethods.InputUnion
            {
                Keyboard = new NativeMethods.KeyboardInput { VirtualKey = key, Flags = flags, ExtraInfo = InjectionMarker },
            },
        };
    }

    private void RecordInjectionFailure(string kind)
    {
        Interlocked.Increment(ref _injectionFailures);
        _log.Write($"SendInput failed kind={kind}; Windows UIPI may block input into elevated applications");
    }

    private bool GetConsumed(MouseButton button) => button switch
    {
        MouseButton.Middle => _middleConsumed,
        MouseButton.Back => _backConsumed,
        MouseButton.Forward => _forwardConsumed,
        _ => false,
    };

    private void SetConsumed(MouseButton button, bool value)
    {
        switch (button)
        {
            case MouseButton.Middle: _middleConsumed = value; break;
            case MouseButton.Back: _backConsumed = value; break;
            case MouseButton.Forward: _forwardConsumed = value; break;
        }
    }

    public void Dispose()
    {
        nint hook = Interlocked.Exchange(ref _hook, 0);
        if (hook != 0)
        {
            _ = NativeMethods.UnhookWindowsHookEx(hook);
            _log.Write("mouse hook stopped");
        }
    }

    private enum MouseButton { Unknown, Middle, Back, Forward }
}
