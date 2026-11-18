using System;
using System.Collections.Generic;
using CodexDesktopKit;
class LaunchTests
{
    class Fake : ILaunchOperations {
        public List<string> Calls=new List<string>();
        public bool Proxy=true,Bridge=true,Restore=true,FailOrb=false,Magpie=true;
        public bool ProxyReady(){Calls.Add("proxy");return Proxy;}
        public bool BridgeReady(){Calls.Add("bridge");return Bridge;}
        public bool RestoreBridge(){Calls.Add("restore");return Restore;}
        public bool MagpieReady(){Calls.Add("magpie");return Magpie;}
        public void ActivateCodex(){Calls.Add("codex");}
        public void StartQuotaOrb(){Calls.Add("orb");if(FailOrb)throw new Exception();}
        public void Log(string value){Calls.Add("log:"+value);}
    }
    static void Assert(bool value,string message){if(!value)throw new Exception(message);}
    static int Main(){
        var f=new Fake();Assert(LaunchPlan.Run(f,false,false)==0,"proxy-only startup");Assert(String.Join(",",f.Calls)=="proxy,codex","optional components ran without selection");
        f=new Fake{FailOrb=true};Assert(LaunchPlan.Run(f,true,true)==0,"orb blocked Codex");Assert(f.Calls.IndexOf("codex")<f.Calls.IndexOf("orb"),"orb preceded required activation");
        f=new Fake{Proxy=false};Assert(LaunchPlan.Run(f,true,true)==2&&!f.Calls.Contains("codex"),"unavailable proxy silently changed route");
        f=new Fake{Bridge=false};Assert(LaunchPlan.Run(f,true,false)==0&&f.Calls.IndexOf("restore")<f.Calls.IndexOf("codex"),"fallback did not restore before activation");
        f=new Fake{Bridge=false,Restore=false};Assert(LaunchPlan.Run(f,true,true)==3&&!f.Calls.Contains("codex")&&!f.Calls.Contains("orb"),"unsafe fallback opened Codex");
        f=new Fake();Assert(LaunchPlan.Run(f,false,true,true)==0,"Magpie startup failed");Assert(String.Join(",",f.Calls)=="proxy,magpie,codex,orb","Magpie mode started bridge or changed order");
        f=new Fake{Magpie=false};Assert(LaunchPlan.Run(f,false,true,true)==4&&!f.Calls.Contains("codex")&&!f.Calls.Contains("bridge")&&!f.Calls.Contains("restore"),"Magpie failure changed the model route or activated Codex");
        f=new Fake{FailOrb=true};Assert(LaunchPlan.Run(f,false,true,true)==0,"Orb failure blocked Magpie mode");
        f=new Fake();Assert(LaunchPlan.Run(f,true,true,true)==4&&!f.Calls.Contains("proxy"),"conflicting gateways ran");
        Console.WriteLine("Launch behavior: proxy-only, optional failure, unavailable proxy, safe fallback and restore conflict passed.");return 0;
    }
}
