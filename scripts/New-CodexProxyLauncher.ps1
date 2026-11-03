# Compatibility build-only entry. New installations use the root install.ps1.
[CmdletBinding()]
param(
    [string]$ProxyHost = '127.0.0.1',
    [ValidateRange(1, 65535)]
    [int]$ProxyPort = 7897,
    [string]$OutputDirectory = (Get-Location).Path,
    [string]$FileName = 'Codex-Clash-7897.exe',
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartMenuShortcut,
    [switch]$DiagnoseOnly
)

$ErrorActionPreference = 'Stop'
if ($ProxyHost -notmatch '^[A-Za-z0-9.:-]+$') { throw 'ProxyHost contains unsupported characters.' }
if ([IO.Path]::GetExtension($FileName) -ne '.exe') { throw 'FileName must end in .exe.' }

function New-IcoFromPngFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PngPaths,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Add-Type -AssemblyName System.Drawing
    $frames = @()
    foreach ($pngPath in $PngPaths) {
        $image = [Drawing.Image]::FromFile($pngPath)
        try {
            if ($image.Width -ne $image.Height -or $image.Width -gt 256) { continue }
            $frames += [pscustomobject]@{
                Width = [int]$image.Width
                Height = [int]$image.Height
                Bytes = [IO.File]::ReadAllBytes($pngPath)
            }
        } finally {
            $image.Dispose()
        }
    }
    if ($frames.Count -eq 0) { throw 'No usable square PNG frames were found for the launcher icon.' }

    $stream = [IO.File]::Create($Destination)
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$frames.Count)
        $offset = 6 + (16 * $frames.Count)
        foreach ($frame in $frames) {
            $widthByte = if ($frame.Width -ge 256) { 0 } else { $frame.Width }
            $heightByte = if ($frame.Height -ge 256) { 0 } else { $frame.Height }
            $writer.Write([byte]$widthByte)
            $writer.Write([byte]$heightByte)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1
if (-not $package) { throw 'OpenAI.Codex Store package was not found for the current user.' }
$manifest = Get-AppxPackageManifest -Package $package
$application = $manifest.Package.Applications.Application | Select-Object -First 1
$aumid = '{0}!{1}' -f $package.PackageFamilyName, $application.Id

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'The .NET Framework C# compiler csc.exe was not found.' }

$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null
$outputExe = Join-Path $resolvedOutput $FileName
$sourceFile = Join-Path ([IO.Path]::GetTempPath()) ('codex-proxy-launcher-{0}.cs' -f [guid]::NewGuid().ToString('N'))
$generatedIcon = Join-Path ([IO.Path]::GetTempPath()) ('codex-proxy-launcher-{0}.ico' -f [guid]::NewGuid().ToString('N'))
$proxyUrl = "http://${ProxyHost}:$ProxyPort"
$diagnoseLiteral = if ($DiagnoseOnly) { 'true' } else { 'false' }

$source = @'
using System;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CodexProxyLauncher
{
    [Flags]
    internal enum ActivateOptions
    {
        None = 0
    }

    [ComImport]
    [Guid("2e941141-7f97-4756-ba1d-9decde894a3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments,
            ActivateOptions options,
            out uint processId);

        int ActivateForFile(string appUserModelId, IntPtr itemArray, string verb, out uint processId);
        int ActivateForProtocol(string appUserModelId, IntPtr itemArray, out uint processId);
    }

    [ComImport]
    [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManager { }

    internal static class Program
    {
        private const string Aumid = "__AUMID__";
        private const string ProxyHost = "__PROXY_HOST__";
        private const int ProxyPort = __PROXY_PORT__;
        private const string ProxyUrl = "__PROXY_URL__";
        private static readonly bool DiagnoseOnly = __DIAGNOSE_ONLY__;

        [STAThread]
        private static int Main()
        {
            try
            {
                if (!IsProxyListening())
                {
                    MessageBox.Show(
                        "The fixed proxy " + ProxyHost + ":" + ProxyPort + " is not listening. Start Clash/Mihomo first.",
                        "Codex proxy unavailable",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning);
                    return 2;
                }

                if (DiagnoseOnly)
                {
                    MessageBox.Show(
                        "AUMID: " + Aumid + Environment.NewLine + "Proxy: " + ProxyUrl + Environment.NewLine + "Listener: OK",
                        "Codex proxy launcher diagnostic",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information);
                    return 0;
                }

                Environment.SetEnvironmentVariable("HTTP_PROXY", ProxyUrl, EnvironmentVariableTarget.Process);
                Environment.SetEnvironmentVariable("HTTPS_PROXY", ProxyUrl, EnvironmentVariableTarget.Process);
                Environment.SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1,::1", EnvironmentVariableTarget.Process);
                Environment.SetEnvironmentVariable("NODE_USE_ENV_PROXY", "1", EnvironmentVariableTarget.Process);

                string arguments = "--proxy-server=\"" + ProxyUrl + "\" --proxy-bypass-list=\"localhost;127.0.0.1;[::1];<local>\"";
                var manager = (IApplicationActivationManager)new ApplicationActivationManager();
                uint processId;
                int hr = manager.ActivateApplication(Aumid, arguments, ActivateOptions.None, out processId);
                Marshal.ThrowExceptionForHR(hr);
                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Unable to start Codex", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static bool IsProxyListening()
        {
            using (var client = new TcpClient())
            {
                try
                {
                    var task = client.ConnectAsync(ProxyHost, ProxyPort);
                    return task.Wait(TimeSpan.FromMilliseconds(1500)) && client.Connected;
                }
                catch
                {
                    return false;
                }
            }
        }
    }
}
'@

$source = $source.Replace('__AUMID__', $aumid.Replace('"', '\"'))
$source = $source.Replace('__PROXY_HOST__', $ProxyHost.Replace('"', '\"'))
$source = $source.Replace('__PROXY_PORT__', $ProxyPort.ToString())
$source = $source.Replace('__PROXY_URL__', $proxyUrl.Replace('"', '\"'))
$source = $source.Replace('__DIAGNOSE_ONLY__', $diagnoseLiteral)

$appsUseLightTheme = 1
try {
    $theme = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if ($null -ne $theme.AppsUseLightTheme) { $appsUseLightTheme = [int]$theme.AppsUseLightTheme }
} catch {}
$iconVariant = if ($appsUseLightTheme -eq 0) { 'unplated' } else { 'lightunplated' }
$iconSizes = 16, 20, 24, 30, 32, 36, 40, 44, 48, 60, 64, 72, 80, 96, 256
$iconPngs = foreach ($size in $iconSizes) {
    $candidate = Join-Path $package.InstallLocation "assets\Square44x44Logo.targetsize-${size}_altform-${iconVariant}.png"
    if (Test-Path -LiteralPath $candidate) { $candidate }
}
New-IcoFromPngFiles -PngPaths $iconPngs -Destination $generatedIcon

$backupExe = $null
if (Test-Path -LiteralPath $outputExe) {
    $backupExe = '{0}.bak-{1}' -f $outputExe, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $outputExe -Destination $backupExe
}

$arguments = @('/nologo', '/target:winexe', '/optimize+', '/platform:anycpu', '/reference:System.Windows.Forms.dll', "/out:$outputExe")
$arguments += "/win32icon:$generatedIcon"
$arguments += $sourceFile

try {
    [IO.File]::WriteAllText($sourceFile, $source, [Text.UTF8Encoding]::new($false))
    & $csc @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputExe)) { throw "csc.exe failed with exit code $LASTEXITCODE." }
} finally {
    if (Test-Path -LiteralPath $sourceFile) { Remove-Item -LiteralPath $sourceFile -Force }
    if (Test-Path -LiteralPath $generatedIcon) { Remove-Item -LiteralPath $generatedIcon -Force }
}

$shell = New-Object -ComObject WScript.Shell
if ($CreateDesktopShortcut) {
    $desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex (Clash 7897).lnk'
    $shortcut = $shell.CreateShortcut($desktopLink)
    $shortcut.TargetPath = $outputExe
    $shortcut.WorkingDirectory = $resolvedOutput
    $shortcut.IconLocation = "$outputExe,0"
    $shortcut.Save()
}
if ($CreateStartMenuShortcut) {
    $startLink = Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs\Codex (Clash 7897).lnk'
    $shortcut = $shell.CreateShortcut($startLink)
    $shortcut.TargetPath = $outputExe
    $shortcut.WorkingDirectory = $resolvedOutput
    $shortcut.IconLocation = "$outputExe,0"
    $shortcut.Save()
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CodexLauncherShellRefresh
{
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
}
'@
[CodexLauncherShellRefresh]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

$hash = (Get-FileHash -LiteralPath $outputExe -Algorithm SHA256).Hash
[pscustomobject]@{
    Launcher = $outputExe
    SHA256 = $hash
    AUMID = $aumid
    Proxy = $proxyUrl
    IconVariant = $iconVariant
    BackupLauncher = $backupExe
    DiagnoseOnly = [bool]$DiagnoseOnly
    DesktopShortcutCreated = [bool]$CreateDesktopShortcut
    StartMenuShortcutCreated = [bool]$CreateStartMenuShortcut
}
