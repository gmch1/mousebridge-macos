// SPDX-License-Identifier: GPL-3.0-or-later

namespace MouseBridge.Windows;

internal static class Program
{
    private const string MutexName = "Local\\MouseBridge.Windows.Singleton";
    private const string ShowEventName = "Local\\MouseBridge.Windows.ShowSettings";

    [STAThread]
    private static int Main(string[] arguments)
    {
        if (arguments.Contains("--self-test", StringComparer.Ordinal)) return SelfTest.Run();
        if (arguments.Length > 0) return CommandLineInterface.Run(arguments);
        if (!OperatingSystem.IsWindows())
        {
            Console.Error.WriteLine("MouseBridge Windows requires Windows 10 or later.");
            return 1;
        }

        if (NativeMethods.GetConsoleWindow() != 0) _ = NativeMethods.FreeConsole();
        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, eventArgs) =>
        {
            DiagnosticLog.Shared.Write($"unhandled UI exception: {eventArgs.Exception.GetType().Name}: {eventArgs.Exception.Message}");
            MessageBox.Show(eventArgs.Exception.Message, Strings.ProductName, MessageBoxButtons.OK, MessageBoxIcon.Error);
        };
        AppDomain.CurrentDomain.UnhandledException += (_, eventArgs) =>
            DiagnosticLog.Shared.Write($"unhandled exception: {eventArgs.ExceptionObject.GetType().Name}");

        using EventWaitHandle showEvent = new(false, EventResetMode.AutoReset, ShowEventName);
        using Mutex mutex = new(true, MutexName, out bool createdNew);
        if (!createdNew)
        {
            showEvent.Set();
            return 0;
        }

        DiagnosticLog.Shared.Write($"launch version=0.1.0-preview pid={Environment.ProcessId}");
        try
        {
            using MouseBridgeContext context = new(showEvent);
            Application.Run(context);
            return 0;
        }
        finally
        {
            try { mutex.ReleaseMutex(); } catch { }
        }
    }
}
