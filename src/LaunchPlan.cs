using System;

namespace CodexDesktopKit
{
    internal interface ILaunchOperations
    {
        bool ProxyReady();
        bool BridgeReady();
        bool RestoreBridge();
        void ActivateCodex();
        void StartQuotaOrb();
        void Log(string category);
    }

    internal static class LaunchPlan
    {
        public static int Run(ILaunchOperations operations, bool bridge, bool orb)
        {
            if (!operations.ProxyReady()) { operations.Log("proxy-unavailable"); return 2; }
            if (bridge && !operations.BridgeReady() && !operations.RestoreBridge()) {
                operations.Log("bridge-unavailable-restore-needs-review"); return 3;
            }
            operations.ActivateCodex();
            if (orb) {
                try { operations.StartQuotaOrb(); }
                catch { operations.Log("optional-orb-start-failed"); }
            }
            return 0;
        }
    }
}
