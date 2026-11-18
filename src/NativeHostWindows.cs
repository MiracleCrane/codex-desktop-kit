using System;
using System.Runtime.InteropServices;
using System.Text;

namespace CodexDesktopKit
{
    internal sealed class NativeHostWindows
    {
        private readonly Func<int, bool> matchesProcess;
        private IntPtr preferred;
        private delegate bool EnumWindowCallback(IntPtr window, IntPtr context);
        [StructLayout(LayoutKind.Sequential)]
        private struct Rectangle { public int Left, Top, Right, Bottom; }

        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowCallback callback, IntPtr context);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rectangle rectangle);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr64(IntPtr window, int index);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowLong32(IntPtr window, int index);
        [DllImport("kernel32.dll")] private static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern int GetApplicationUserModelId(IntPtr process, ref uint length, StringBuilder value);

        public NativeHostWindows(Func<int, bool> processMatcher) { matchesProcess = processMatcher; }
        public static NativeHostWindows ForApplication(string aumid)
        {
            return new NativeHostWindows(pid => String.Equals(ApplicationId(pid), aumid, StringComparison.OrdinalIgnoreCase));
        }
        private static string ApplicationId(int processId)
        {
            IntPtr process = OpenProcess(0x1000, false, (uint)processId);
            if (process == IntPtr.Zero) return null;
            try
            {
                uint length = 0;
                if (GetApplicationUserModelId(process, ref length, null) != 122 || length == 0 || length > 4096) return null;
                var value = new StringBuilder((int)length);
                return GetApplicationUserModelId(process, ref length, value) == 0 ? value.ToString() : null;
            }
            finally { CloseHandle(process); }
        }
        private HostWindowIdentity Match(IntPtr window)
        {
            if (window == IntPtr.Zero || !IsWindowVisible(window) || GetWindow(window, 4) != IntPtr.Zero) return null;
            long style = IntPtr.Size == 8 ? GetWindowLongPtr64(window, -20).ToInt64() : GetWindowLong32(window, -20);
            if ((style & 0x80) != 0) return null;
            var name = new StringBuilder(256);
            GetClassName(window, name, name.Capacity);
            if (name.ToString() != "Chrome_WidgetWin_0" && name.ToString() != "Chrome_WidgetWin_1") return null;
            Rectangle rectangle;
            if (!GetWindowRect(window, out rectangle)) return null;
            if (!IsIconic(window) && (rectangle.Right - rectangle.Left < 160 || rectangle.Bottom - rectangle.Top < 80)) return null;
            uint pid;
            GetWindowThreadProcessId(window, out pid);
            if (pid == 0 || !matchesProcess((int)pid)) return null;
            return new HostWindowIdentity(window.ToInt64(), (int)pid);
        }
        public HostWindowIdentity Read()
        {
            HostWindowIdentity result = Match(preferred);
            if (result != null) return result;
            EnumWindows(delegate(IntPtr window, IntPtr unused)
            {
                result = Match(window);
                if (result == null) return true;
                preferred = window;
                return false;
            }, IntPtr.Zero);
            return result;
        }
    }
}
