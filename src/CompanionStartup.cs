using System;

namespace CodexDesktopKit
{
    internal sealed class HostWindowIdentity
    {
        public readonly long Handle;
        public readonly int ProcessId;
        public HostWindowIdentity(long handle, int processId) { Handle = handle; ProcessId = processId; }
        public string Key { get { return ProcessId + ":" + Handle; } }
    }

    internal static class CompanionStartup
    {
        public const int ObservationMilliseconds = 120000;
        public const int StableWindowMilliseconds = 750;
        public const int PollMilliseconds = 250;

        // The host is already activated. This finite observer owns only optional
        // companion startup, including a replacement window during an update.
        public static void Observe(Func<HostWindowIdentity> findWindow, Action ensureCompanion,
            Func<long> milliseconds, Action<int> pause, Action<string> log,
            int observationMilliseconds = ObservationMilliseconds,
            int stableWindowMilliseconds = StableWindowMilliseconds)
        {
            long started = milliseconds();
            long candidateSince = started;
            string candidate = null;
            string attempted = null;
            bool launched = false;
            while (milliseconds() - started < observationMilliseconds)
            {
                HostWindowIdentity window = findWindow();
                string key = window == null ? null : window.Key;
                long now = milliseconds();
                if (now - started >= observationMilliseconds) break;
                if (key != candidate)
                {
                    candidate = key;
                    candidateSince = now;
                    attempted = null;
                }
                if (window != null && attempted != key && now - candidateSince >= stableWindowMilliseconds)
                {
                    attempted = key;
                    try
                    {
                        ensureCompanion();
                        launched = true;
                        log("companion-host-ready pid=" + window.ProcessId + " elapsed-ms=" + (now - started));
                    }
                    catch { log("optional-orb-start-failed"); }
                }
                long remaining = observationMilliseconds - (milliseconds() - started);
                if (remaining > 0) pause((int)Math.Min(PollMilliseconds, remaining));
            }
            log(launched ? "companion-startup-observation-finished" : "companion-host-window-timeout");
        }
    }
}
