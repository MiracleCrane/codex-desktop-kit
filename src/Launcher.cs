using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace CodexDesktopKit
{
    internal sealed class BridgeSettings
    {
        public string ReceiptPath { get; set; }
        public string RestoreScript { get; set; }
        public string PowerShellPath { get; set; }
    }
    internal sealed class Settings
    {
        public string Version { get; set; }
        public string Aumid { get; set; }
        public string ProxyUri { get; set; }
        public string NoProxy { get; set; }
        public string ProxyBypassList { get; set; }
        public string CodexHome { get; set; }
        public string LogPath { get; set; }
        public string QuotaOrbPath { get; set; }
        public BridgeSettings Bridge { get; set; }
    }

    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string id,
            [MarshalAs(UnmanagedType.LPWStr)] string args, uint options, out uint pid);
        int ActivateForFile(string id, IntPtr items, string verb, out uint pid);
        int ActivateForProtocol(string id, IntPtr items, out uint pid);
    }
    [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManager { }

    internal sealed class Operations : ILaunchOperations
    {
        private readonly Settings settings;
        private readonly JavaScriptSerializer json = new JavaScriptSerializer();
        public Operations(Settings value) { settings = value; }
        public void Log(string category)
        {
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(settings.LogPath));
                if (File.Exists(settings.LogPath) && new FileInfo(settings.LogPath).Length > 1048576)
                    File.WriteAllText(settings.LogPath, "", new UTF8Encoding(false));
                File.AppendAllText(settings.LogPath, DateTimeOffset.Now.ToString("o") + " " + category + Environment.NewLine);
            } catch { }
        }
        public bool ProxyReady()
        {
            Uri uri = new Uri(settings.ProxyUri);
            if (uri.Scheme != "http" || !uri.IsLoopback || uri.UserInfo.Length != 0 || uri.Port < 1)
                throw new InvalidOperationException("代理地址应为本机 HTTP/mixed 端口，不含账号密码。");
            using (var socket = new TcpClient()) {
                try { return socket.ConnectAsync(uri.DnsSafeHost, uri.Port).Wait(1500) && socket.Connected; }
                catch { return false; }
            }
        }
        private Dictionary<string, object> Receipt()
        {
            return json.Deserialize<Dictionary<string, object>>(File.ReadAllText(settings.Bridge.ReceiptPath));
        }
        private bool Health(Dictionary<string, object> receipt)
        {
            try {
                var request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + receipt["Port"] + "/health");
                request.Proxy = null; request.Timeout = 1000; request.ReadWriteTimeout = 1000;
                using (var response = request.GetResponse())
                using (var reader = new StreamReader(response.GetResponseStream())) {
                    var h = json.Deserialize<Dictionary<string, object>>(reader.ReadToEnd());
                    return Equals(h["ready"], true) && Equals(h["managed"], true)
                        && Equals(h["service"], "codex-transport-bridge")
                        && Equals(h["version"], receipt["Version"]) && Equals(h["instanceId"], receipt["InstanceId"]);
                }
            } catch { return false; }
        }
        public bool BridgeReady()
        {
            try {
                var r = Receipt();
                if (!Equals(r["Mode"], "component") || !Equals(r["Status"], "enabled")) return false;
                if (Health(r)) return true;
                string exe = (string)r["SupervisorPath"];
                using (var stream = File.OpenRead(exe))
                using (var sha = SHA256.Create()) {
                    string actual = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
                    if (!Equals(actual, r["SupervisorSha256"])) return false;
                }
                using (Process.Start(new ProcessStartInfo(exe, "--guard-only") {
                    UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(exe), WindowStyle = ProcessWindowStyle.Hidden
                })) { }
                for (int i = 0; i < 24; i++) { if (Health(r)) return true; Thread.Sleep(250); }
            } catch { Log("bridge-start-failed"); }
            return false;
        }
        public bool RestoreBridge()
        {
            try {
                var r = Receipt();
                var transaction = json.Deserialize<Dictionary<string, object>>(File.ReadAllText((string)r["ConfigTransaction"]));
                // Do not restore a possibly dead legacy local bridge and call it a fallback.
                if (transaction["previous"] != null) { Log("bridge-fallback-has-previous-route"); return false; }
                var info = new ProcessStartInfo(settings.Bridge.PowerShellPath,
                    "-NoProfile -File \"" + settings.Bridge.RestoreScript + "\" -InstallationPath \"" + settings.Bridge.ReceiptPath + "\" -Confirm:$false") {
                    UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
                };
                using (var process = Process.Start(info)) {
                    if (!process.WaitForExit(15000) || process.ExitCode != 0) return false;
                }
                // Restore owns the field only while its transaction value is still installed.
                // If an independent edit replaced it, preserve it and require review.
                var inspect = new ProcessStartInfo((string)r["PythonPath"],
                    "-X utf8 \"" + Path.Combine(Path.GetDirectoryName(settings.Bridge.RestoreScript), "config-edit.py")
                    + "\" inspect --state \"" + r["ConfigTransaction"] + "\"") {
                    UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true
                };
                using (var process = Process.Start(inspect)) {
                    if (!process.WaitForExit(5000) || process.ExitCode != 0) return false;
                    var status = json.Deserialize<Dictionary<string, object>>(process.StandardOutput.ReadToEnd());
                    if (!Equals(status["hasBaseUrl"], false)) return false;
                }
                Log("bridge-restored-to-original-proxy-route");
                return true;
            } catch { Log("bridge-restore-failed"); return false; }
        }
        private void ConfigureProcessEnvironment()
        {
            foreach (string key in new[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY" })
                Environment.SetEnvironmentVariable(key, settings.ProxyUri, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("NO_PROXY", settings.NoProxy, EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("NODE_USE_ENV_PROXY", "1", EnvironmentVariableTarget.Process);
            Environment.SetEnvironmentVariable("CODEX_HOME", settings.CodexHome, EnvironmentVariableTarget.Process);
        }
        public void ActivateCodex()
        {
            ConfigureProcessEnvironment();
            string args = "--proxy-server=\"" + settings.ProxyUri + "\" --proxy-bypass-list=\"" + settings.ProxyBypassList + "\"";
            var manager = (IApplicationActivationManager)new ApplicationActivationManager();
            uint pid;
            Marshal.ThrowExceptionForHR(manager.ActivateApplication(settings.Aumid, args, 0, out pid));
            Log("codex-activation-requested pid=" + pid);
        }
        public void StartQuotaOrb()
        {
            var windows = NativeHostWindows.ForApplication(settings.Aumid);
            var clock = Stopwatch.StartNew();
            CompanionStartup.Observe(windows.Read, () => StartQuotaOrbWith("--ensure-running"),
                () => clock.ElapsedMilliseconds, Thread.Sleep, Log);
        }
        public void ToggleQuotaOrb() { StartQuotaOrbWith("--toggle"); }
        private void StartQuotaOrbWith(string argument)
        {
            ConfigureProcessEnvironment();
            using (Process.Start(new ProcessStartInfo(settings.QuotaOrbPath, argument) {
                UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(settings.QuotaOrbPath), WindowStyle = ProcessWindowStyle.Hidden
            })) { }
            Log("quota-orb-start-requested");
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            try {
                if ((args.Length != 2 && args.Length != 3) || args[0] != "--config"
                    || (args.Length == 3 && args[2] != "--toggle-orb")) throw new InvalidOperationException("请使用安装器创建的快捷方式。");
                var settings = new JavaScriptSerializer().Deserialize<Settings>(File.ReadAllText(Path.GetFullPath(args[1])));
                if (String.IsNullOrEmpty(settings.Aumid) || String.IsNullOrEmpty(settings.CodexHome)
                    || (settings.ProxyBypassList ?? "").IndexOfAny(new[] { '"', '\r', '\n' }) >= 0)
                    throw new InvalidOperationException("启动配置不完整，请通过安装器修复。");
                var operations = new Operations(settings);
                if (args.Length == 3) {
                    if (String.IsNullOrEmpty(settings.QuotaOrbPath)) throw new InvalidOperationException("未安装悬浮球组件。");
                    operations.ToggleQuotaOrb();
                    return 0;
                }
                int result = LaunchPlan.Run(operations, settings.Bridge != null, !String.IsNullOrEmpty(settings.QuotaOrbPath));
                if (result == 2) MessageBox.Show("本地代理端口未就绪。请启动代理客户端的 HTTP/mixed 端口后重试；无需开启 TUN 或系统代理。", "Codex Desktop Kit");
                if (result == 3) MessageBox.Show("桥接未就绪，连接配置需要检查。请运行 Test-Kit.ps1；现有聊天与用户配置已保留。", "Codex Desktop Kit");
                return result;
            } catch {
                MessageBox.Show("无法完成 Codex 启动，请运行套件的 Test-Kit.ps1 查看安装状态。", "Codex Desktop Kit");
                return 1;
            }
        }
    }
}
