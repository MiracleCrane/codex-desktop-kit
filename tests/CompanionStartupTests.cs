using System;
using System.Collections.Generic;
using CodexDesktopKit;

class CompanionStartupTests
{
    class Scenario
    {
        public long Now;
        public Func<long, HostWindowIdentity> Window;
        public List<long> Starts = new List<long>();
        public List<string> Logs = new List<string>();
        public bool FailStart;
        public void Run()
        {
            CompanionStartup.Observe(() => Window(Now), () => {
                Starts.Add(Now);
                if (FailStart) throw new Exception("fixture");
            }, () => Now, ms => Now += ms, Logs.Add);
        }
    }
    static HostWindowIdentity Host(long handle = 1, int pid = 10) { return new HostWindowIdentity(handle, pid); }
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static int Main()
    {
        var s = new Scenario { Window = t => t >= 58000 ? Host() : null };
        s.Run(); Check(s.Starts.Count == 1 && s.Starts[0] >= 58000 && s.Starts[0] < 60000, "58-second startup launched the companion too early or never");
        s = new Scenario { Window = t => null };
        s.Run(); Check(s.Starts.Count == 0 && s.Now == 120000 && s.Logs.Contains("companion-host-window-timeout"), "Missing window was not bounded");
        s = new Scenario { Window = t => Host() };
        s.Run(); Check(s.Starts.Count == 1 && s.Starts[0] == 750, "Existing window should start promptly and only once");
        s = new Scenario { Window = t => t < 1000 ? Host() : t >= 60000 ? Host(2, 20) : null };
        s.Run(); Check(s.Starts.Count == 2 && s.Starts[1] >= 60000, "Replacement process was tied to the activation PID or missed");
        s = new Scenario { Window = t => t < 250 ? Host() : t >= 58000 ? Host(2, 20) : null };
        s.Run(); Check(s.Starts.Count == 1 && s.Starts[0] >= 58000, "Transient startup window was accepted");
        s = new Scenario { Window = t => t < 1000 || t >= 60000 ? Host() : null };
        s.Run(); Check(s.Starts.Count == 2, "Restored same window did not refresh companion startup");
        s = new Scenario { Window = t => Host(), FailStart = true };
        s.Run(); Check(s.Starts.Count == 1 && s.Logs.Contains("optional-orb-start-failed") && s.Now == 120000, "Optional startup failure looped or escaped");
        Console.WriteLine("Companion readiness: 58-second startup, no window, existing window, process replacement, transient/restored window and optional failure passed (virtual clock).");
        return 0;
    }
}
