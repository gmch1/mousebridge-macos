// SPDX-License-Identifier: GPL-3.0-or-later

using System.Runtime.InteropServices;

namespace MouseBridge.Windows;

internal sealed record HidInterfaceInfo(
    string Path,
    ushort VendorId,
    ushort ProductId,
    ushort UsagePage,
    ushort Usage,
    ushort InputReportLength,
    ushort OutputReportLength);

internal static class HidDeviceEnumerator
{
    private const int ErrorNoMoreItems = 259;
    private static readonly nint InvalidHandleValue = new(-1);

    public static IReadOnlyList<HidInterfaceInfo> EnumerateM750(DiagnosticLog? log = null)
    {
        if (!OperatingSystem.IsWindows()) return [];
        DiagnosticLog logger = log ?? DiagnosticLog.Shared;
        NativeMethods.HidD_GetHidGuid(out Guid hidGuid);
        nint devices = NativeMethods.SetupDiGetClassDevsW(
            ref hidGuid,
            0,
            0,
            NativeMethods.DigcfPresent | NativeMethods.DigcfDeviceInterface);
        if (devices == InvalidHandleValue)
        {
            logger.Write($"SetupAPI HID enumeration open failed: {Marshal.GetLastWin32Error()}");
            return [];
        }

        List<HidInterfaceInfo> matches = [];
        try
        {
            for (uint index = 0; ; index++)
            {
                NativeMethods.SpDeviceInterfaceData interfaceData = new() { Size = Marshal.SizeOf<NativeMethods.SpDeviceInterfaceData>() };
                if (!NativeMethods.SetupDiEnumDeviceInterfaces(devices, 0, ref hidGuid, index, ref interfaceData))
                {
                    if (Marshal.GetLastWin32Error() != ErrorNoMoreItems)
                        logger.Write($"SetupAPI HID interface enumeration failed index={index} error={Marshal.GetLastWin32Error()}");
                    break;
                }

                _ = NativeMethods.SetupDiGetDeviceInterfaceDetailW(devices, ref interfaceData, 0, 0, out uint requiredSize, 0);
                if (requiredSize == 0) continue;
                nint detail = Marshal.AllocHGlobal(checked((int)requiredSize));
                try
                {
                    Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                    if (!NativeMethods.SetupDiGetDeviceInterfaceDetailW(devices, ref interfaceData, detail, requiredSize, out _, 0))
                        continue;
                    string? path = Marshal.PtrToStringUni(detail + 4);
                    if (string.IsNullOrWhiteSpace(path)) continue;
                    HidInterfaceInfo? info = Inspect(path, logger);
                    if (info is not null) matches.Add(info);
                }
                finally
                {
                    Marshal.FreeHGlobal(detail);
                }
            }
        }
        finally
        {
            _ = NativeMethods.SetupDiDestroyDeviceInfoList(devices);
        }
        return matches;
    }

    private static HidInterfaceInfo? Inspect(string path, DiagnosticLog log)
    {
        using Microsoft.Win32.SafeHandles.SafeFileHandle identityHandle = NativeMethods.CreateFileW(
            path,
            0,
            NativeMethods.FileShareRead | NativeMethods.FileShareWrite,
            0,
            NativeMethods.OpenExisting,
            0,
            0);
        if (identityHandle.IsInvalid) return null;

        NativeMethods.HiddAttributes attributes = new() { Size = Marshal.SizeOf<NativeMethods.HiddAttributes>() };
        if (!NativeMethods.HidD_GetAttributes(identityHandle, ref attributes) || attributes.VendorId != 0x046D || attributes.ProductId != 0xB02C)
            return null;
        using Microsoft.Win32.SafeHandles.SafeFileHandle handle = NativeMethods.CreateFileW(
            path,
            NativeMethods.GenericRead | NativeMethods.GenericWrite,
            NativeMethods.FileShareRead | NativeMethods.FileShareWrite,
            0,
            NativeMethods.OpenExisting,
            NativeMethods.FileFlagOverlapped,
            0);
        if (handle.IsInvalid)
        {
            log.Write($"M750 HID interface open failed error={Marshal.GetLastWin32Error()}");
            return null;
        }
        if (!NativeMethods.HidD_GetPreparsedData(handle, out nint preparsed)) return null;
        try
        {
            if (NativeMethods.HidP_GetCaps(preparsed, out NativeMethods.HidpCaps caps) < 0) return null;
            log.Write($"M750 HID candidate usage={caps.UsagePage:X4}:{caps.Usage:X4} inputReport={caps.InputReportByteLength} outputReport={caps.OutputReportByteLength}");
            return new HidInterfaceInfo(
                path,
                attributes.VendorId,
                attributes.ProductId,
                caps.UsagePage,
                caps.Usage,
                caps.InputReportByteLength,
                caps.OutputReportByteLength);
        }
        finally
        {
            _ = NativeMethods.HidD_FreePreparsedData(preparsed);
        }
    }
}
