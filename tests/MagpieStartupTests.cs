using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using CodexDesktopKit;

class MagpieStartupTests
{
    static void Assert(bool value,string message){if(!value)throw new Exception(message);}
    static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--quota-helper-fixture") {
            using (var stop = EventWaitHandle.OpenExisting(args[1])) stop.WaitOne();
            return 0;
        }
        Assert(MagpieStartup.HealthUri("http://127.0.0.1:3456/backend-api/codex").AbsoluteUri=="http://127.0.0.1:3456/api/hello","health URL changed the origin");
        foreach(var value in new[]{"https://127.0.0.1:3456/backend-api/codex","http://example.com/backend-api/codex","http://user@127.0.0.1:3456/backend-api/codex","http://127.0.0.1:3456/other","http://127.0.0.1:3456/backend-api/codex?token=x"}){
            bool rejected=false;try{MagpieStartup.HealthUri(value);}catch(InvalidOperationException){rejected=true;}
            Assert(rejected,"unsafe gateway origin accepted");
        }
        Assert(MagpieStartup.AcceptHealth("{\"name\":\"magpie\",\"version\":\"fixture\"}"),"healthy Magpie rejected");
        foreach(var value in new[]{"{\"ready\":true}","{\"name\":\"other\",\"version\":\"fixture\"}","{\"name\":\"magpie\"}","not json"})
            Assert(!MagpieStartup.AcceptHealth(value),"wrong service was accepted");
        int starts=0,probes=0;long now=0;var logs=new List<string>();
        bool result=MagpieStartup.Ensure(()=>true,()=>true,()=>starts++,()=>now,n=>now+=n,logs.Add,1000);
        Assert(result&&starts==0&&logs.Contains("magpie-reused"),"healthy gateway was restarted");
        result=MagpieStartup.Ensure(()=>true,()=>++probes>=4,()=>starts++,()=>now,n=>now+=n,logs.Add,1000);
        Assert(result&&starts==1,"cold gateway was not started once");
        starts=0;probes=0;now=0;
        result=MagpieStartup.Ensure(()=>true,()=>{probes++;return false;},()=>starts++,()=>now,n=>now+=n,logs.Add,1000);
        Assert(!result&&starts==1&&now==1000,"timeout started repeated helpers or was unbounded");
        starts=0;probes=0;
        result=MagpieStartup.Ensure(()=>false,()=>{probes++;return true;},()=>starts++,()=>now,n=>now+=n,logs.Add,1000);
        Assert(!result&&starts==0&&probes==0,"changed model route was ignored");
        result=MagpieStartup.Ensure(()=>true,()=>false,()=>{throw new Exception();},()=>now,n=>now+=n,logs.Add,1000);
        Assert(!result&&logs.Contains("magpie-start-failed"),"start failure was hidden");
        bool route=true,healthy=false;
        result=MagpieStartup.Ensure(()=>route,()=>healthy,()=>{healthy=true;route=false;},()=>now,n=>now+=n,logs.Add,1000);
        Assert(!result&&logs.Contains("magpie-route-changed"),"route changed during gateway startup but was accepted");
        int reconnects=0;route=false;
        Assert(!MagpieStartup.Prepare(()=>route,true,()=>false,()=>{reconnects++;route=true;},logs.Add)&&reconnects==0,"running Codex was reconnected");
        Assert(!MagpieStartup.Prepare(()=>route,false,()=>true,()=>{reconnects++;route=true;},logs.Add)&&reconnects==0,"reconnect ran without selection");
        Assert(MagpieStartup.Prepare(()=>route,true,()=>true,()=>{reconnects++;route=true;},logs.Add)&&reconnects==1,"stopped Codex was not reconnected");
        Assert(MagpieStartup.Prepare(()=>route,true,()=>false,()=>reconnects++,logs.Add)&&reconnects==1,"already connected route was rewritten");
        int stops=0; bool helperAlive=true; now=0;
        Assert(MagpieStartup.WaitForClients(()=>true,()=>!helperAlive,()=>{stops++;helperAlive=false;},()=>now,n=>now+=n,logs.Add,500)
            && stops==1,"the orb's quota helper blocked reconnect after the desktop exited");
        stops=0;
        Assert(!MagpieStartup.WaitForClients(()=>false,()=>false,()=>stops++,()=>now,n=>now+=n,logs.Add,500)
            && stops==0,"a running desktop caused its companion to be stopped");
        now=0;stops=0;
        Assert(!MagpieStartup.WaitForClients(()=>true,()=>false,()=>stops++,()=>now,n=>now+=n,logs.Add,500)
            && stops==1 && now==500,"a real CLI was ignored or the close wait was unbounded");
        bool desktopGone=true;stops=0;
        Assert(!MagpieStartup.WaitForClients(()=>desktopGone,()=>false,()=>{stops++;desktopGone=false;},()=>now,n=>now+=n,logs.Add,500)
            && stops==1,"a desktop reopened during cleanup but reconnect was allowed");
        stops=0;
        Assert(MagpieStartup.WaitForClients(()=>true,()=>true,()=>stops++,()=>now,n=>now+=n,logs.Add,500)
            && stops==0,"cleanup was requested when no Codex process remained");
        Assert(!MagpieStartup.WaitForClients(()=>true,()=>false,()=>{throw new Exception();},()=>now,n=>now+=n,logs.Add,500)
            && logs.Contains("quota-orb-stop-for-reconnect-failed"),"companion cleanup failure allowed reconnect");
        string signalName="Local\\lzc-quota-helper-"+Guid.NewGuid().ToString("N");
        using (var stop=new EventWaitHandle(false,EventResetMode.ManualReset,signalName))
        using (var helper=Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,
            "--quota-helper-fixture "+signalName){UseShellExecute=false,CreateNoWindow=true})) {
            try {
                Assert(!MagpieStartup.Prepare(()=>false,true,()=>helper.HasExited,()=>{throw new Exception("must not reconnect");},logs.Add),
                    "the original guard unexpectedly accepted the lingering helper");
                var clock=Stopwatch.StartNew();
                Assert(MagpieStartup.WaitForClients(()=>true,()=>helper.HasExited,()=>stop.Set(),()=>clock.ElapsedMilliseconds,Thread.Sleep,logs.Add)
                    && helper.HasExited,"native helper did not exit before reconnect was allowed");
            } finally { if(!helper.HasExited){stop.Set();if(!helper.WaitForExit(2000))helper.Kill();} }
        }
        Console.WriteLine("Magpie readiness: identity, origin, reuse, cold start, timeout and route ownership passed.");
        return 0;
    }
}
