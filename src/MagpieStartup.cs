using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Web.Script.Serialization;

namespace CodexDesktopKit
{
    internal static class MagpieStartup
    {
        public static bool Prepare(Func<bool> matches, bool reconnectEnabled, Func<bool> clientsStopped,
            Action reconnect, Action<string> log)
        {
            if (matches()) return true;
            if (!reconnectEnabled) { log("magpie-route-mismatch"); return false; }
            if (!clientsStopped()) { log("magpie-reconnect-needs-codex-exit"); return false; }
            try { reconnect(); }
            catch { log("magpie-reconnect-failed"); return false; }
            if (!matches()) { log("magpie-reconnect-route-mismatch"); return false; }
            log("magpie-reconnected");
            return true;
        }
        public static Uri HealthUri(string baseUrl)
        {
            Uri uri;
            if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out uri) || uri.Scheme != "http"
                || !uri.IsLoopback || uri.UserInfo.Length != 0 || uri.Query.Length != 0
                || uri.Fragment.Length != 0 || uri.AbsolutePath.TrimEnd('/') != "/backend-api/codex")
                throw new InvalidOperationException("Magpie 模型入口必须是本机 HTTP 网关的 /backend-api/codex 路径。");
            return new Uri(uri.GetLeftPart(UriPartial.Authority) + "/api/hello");
        }

        public static bool AcceptHealth(string body)
        {
            try {
                var data = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(body);
                object name, version;
                return data != null && data.TryGetValue("name", out name) && Equals(name, "magpie")
                    && data.TryGetValue("version", out version) && version is string
                    && !String.IsNullOrWhiteSpace((string)version);
            } catch { return false; }
        }

        public static bool Ready(string baseUrl)
        {
            try {
                var request = (HttpWebRequest)WebRequest.Create(HealthUri(baseUrl));
                request.Proxy = null; request.Timeout = 1000; request.ReadWriteTimeout = 1000;
                request.AllowAutoRedirect = false;
                using (var response = (HttpWebResponse)request.GetResponse())
                using (var reader = new StreamReader(response.GetResponseStream())) {
                    if (response.StatusCode != HttpStatusCode.OK) return false;
                    var buffer = new char[8193];
                    int count = reader.ReadBlock(buffer, 0, buffer.Length);
                    return count <= 8192 && AcceptHealth(new string(buffer, 0, count));
                }
            } catch { return false; }
        }

        public static bool Ensure(Func<bool> routeMatches, Func<bool> ready, Action start,
            Func<long> clock, Action<int> sleep, Action<string> log, int timeoutMs = 30000)
        {
            if (!routeMatches()) { log("magpie-route-mismatch"); return false; }
            if (ready()) {
                if (!routeMatches()) { log("magpie-route-changed"); return false; }
                log("magpie-reused"); return true;
            }
            try { start(); }
            catch { log("magpie-start-failed"); return false; }
            long until = clock() + timeoutMs;
            while (clock() < until) {
                if (ready()) {
                    if (!routeMatches()) { log("magpie-route-changed"); return false; }
                    log("magpie-ready"); return true;
                }
                sleep(250);
            }
            log("magpie-ready-timeout");
            return false;
        }
    }
}
