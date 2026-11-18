using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using CodexDesktopKit;

class NativeWindowFixtureTests
{
    private delegate IntPtr WindowProcedure(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam);
    private static readonly WindowProcedure Procedure = ProcessMessage;
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size, Style;
        public IntPtr Procedure;
        public int ClassExtra, WindowExtra;
        public IntPtr Instance, Icon, Cursor, Background;
        public string Menu, Name;
        public IntPtr SmallIcon;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        public IntPtr Window;
        public uint Id;
        public UIntPtr Wparam;
        public IntPtr Lparam;
        public uint Time;
        public int X, Y;
        public uint Private;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WindowClass value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(uint extendedStyle, string name, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern UIntPtr SetTimer(IntPtr window, UIntPtr id, uint milliseconds, IntPtr callback);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern void PostQuitMessage(int code);
    [DllImport("user32.dll")] static extern int GetMessage(out Message message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref Message message);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam);

    static IntPtr ProcessMessage(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam)
    {
        if (message == 0x113) { DestroyWindow(window); return IntPtr.Zero; }
        if (message == 2) { PostQuitMessage(0); return IntPtr.Zero; }
        return DefWindowProc(window, message, wparam, lparam);
    }
    static void CreateFixture(int delayMilliseconds)
    {
        Thread.Sleep(delayMilliseconds);
        var cls = new WindowClass { Size = (uint)Marshal.SizeOf(typeof(WindowClass)),
            Procedure = Marshal.GetFunctionPointerForDelegate(Procedure), Instance = GetModuleHandle(null),
            Name = "Chrome_WidgetWin_1", Background = new IntPtr(6) };
        if (RegisterClassEx(ref cls) == 0) throw new Exception("Fixture class registration failed");
        // A real top-level native window, placed offscreen and shown without focus.
        IntPtr window = CreateWindowEx(0, cls.Name, "lzc startup fixture", 0x00CF0000,
            -20000, -20000, 320, 200, IntPtr.Zero, IntPtr.Zero, cls.Instance, IntPtr.Zero);
        if (window == IntPtr.Zero) throw new Exception("Fixture window creation failed");
        ShowWindow(window, 4);
        SetTimer(window, new UIntPtr(1), 4000, IntPtr.Zero);
        Message message;
        while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref message); DispatchMessage(ref message); }
    }
    static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--live-probe")
        {
            var host = NativeHostWindows.ForApplication(args[1]).Read();
            Console.WriteLine(host == null ? "No matching host window" : "Matched host pid=" + host.ProcessId + " hwnd=" + host.Handle);
            return host == null ? 2 : 0;
        }
        int delay = args.Length == 1 ? Int32.Parse(args[0]) : 58000;
        var clock = Stopwatch.StartNew();
        var starts = new List<long>();
        int pid = Process.GetCurrentProcess().Id;
        var windows = new NativeHostWindows(candidate => candidate == pid);
        var worker = new Thread(() => CreateFixture(delay));
        worker.SetApartmentState(ApartmentState.STA);
        worker.IsBackground = true;
        worker.Start();
        CompanionStartup.Observe(windows.Read, () => starts.Add(clock.ElapsedMilliseconds),
            () => clock.ElapsedMilliseconds, Thread.Sleep, Console.WriteLine, delay + 6500);
        if (!worker.Join(1000)) throw new Exception("Fixture window thread did not exit");
        if (starts.Count != 1 || starts[0] < delay || starts[0] >= delay + 4000)
            throw new Exception("Native window readiness failed: count=" + starts.Count);
        Console.WriteLine("Native delayed-window fixture passed: delay-ms=" + delay + " companion-start-ms=" + starts[0]);
        return 0;
    }
}
