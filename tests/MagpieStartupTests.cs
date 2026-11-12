using System;
using System.Collections.Generic;
using CodexDesktopKit;

class MagpieStartupTests
{
    static void Assert(bool value,string message){if(!value)throw new Exception(message);}
    static int Main()
    {
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
        Console.WriteLine("Magpie readiness: identity, origin, reuse, cold start, timeout and route ownership passed.");
        return 0;
    }
}
