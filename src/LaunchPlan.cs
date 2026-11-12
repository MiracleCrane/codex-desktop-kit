using System;

namespace CodexDesktopKit
{
    internal interface ILaunchOperations
    {
        bool ProxyReady();
        bool BridgeReady();
        bool RestoreBridge();
        bool MagpieReady();
        void ActivateCodex();
        void StartQuotaOrb();
        void Log(string category);
    }

    internal static class LaunchPlan
    {
        public static int Run(ILaunchOperations operations, bool bridge, bool orb, bool magpie = false)
        {
            if (bridge && magpie) { operations.Log("conflicting-model-gateways"); return 4; }
            if (!operations.ProxyReady()) { operations.Log("proxy-unavailable"); return 2; }
            if (magpie && !operations.MagpieReady()) { operations.Log("magpie-unavailable-route-preserved"); return 4; }
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
