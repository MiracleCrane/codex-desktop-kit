# Explicit, workstation-local compatibility entrypoint. Not a default kit mode.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('Compatibility','Original')][string]$Mode='Compatibility',
    [switch]$PrepareOnly,
    [switch]$PackageWorker
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Write-AtomicJson($Value, [string]$Path) {
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, "$Path.previous", $true) }
    else { [IO.File]::Move($temp, $Path) }
}
function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Assert-Official([string]$Path) {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne 'Valid' -or !$sig.SignerCertificate -or
        $sig.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)(?:CN|O)="?OpenAI(?:,|\s|$)') {
        throw "Expected a valid OpenAI signature: $([IO.Path]::GetFileName($Path))"
    }
}
$c = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($c.Enabled -ne $true -or $c.ComputerName -ine $env:COMPUTERNAME) {
    throw 'This opt-in profile is disabled or belongs to a different computer.'
}
foreach ($name in @('CodexHome','CacheRoot')) {
    if (![IO.Path]::IsPathRooted([string]$c.$name)) { throw "$name must be an absolute local path." }
}
if (!(Test-Path -LiteralPath $c.CodexHome -PathType Container)) { throw 'Existing Codex home not found; refusing to create a new empty home.' }
$proxy = [uri]$c.ProxyUri
if (!$proxy.IsAbsoluteUri -or $proxy.Scheme -ne 'http' -or !$proxy.IsLoopback -or $proxy.UserInfo) {
    throw 'ProxyUri must be a local HTTP proxy without credentials.'
}
foreach ($value in @($c.NoProxy,$c.ProxyBypassList)) {
    if ([string]$value -match '["\r\n]') { throw 'Invalid proxy bypass value.' }
}
# Do not replace a live desktop/backend or spawn a second instance.
$active = @(Get-Process -Name ChatGPT,codex,tran -ErrorAction SilentlyContinue)
if ($active.Count -gt 0 -and !$PrepareOnly) {
    throw 'Codex/backend is already running. Keep using it, or exit normally before launching. No process was stopped.'
}
$packages = @(Get-AppxPackage -Name OpenAI.Codex | Sort-Object { [version]$_.Version } -Descending)
if ($packages.Count -eq 0) { throw 'Official Codex package is not installed for this user.' }
$package = $packages[0]
$app = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
$resources = Join-Path $package.InstallLocation 'app\resources'
$source = Join-Path $resources 'codex.exe'
Assert-Official $app
Assert-Official $source
$sourceHash = Get-Hash $source
$version = [string]$package.Version
$cache = [IO.Path]::GetFullPath([string]$c.CacheRoot)
[IO.Directory]::CreateDirectory($cache) | Out-Null
# An exclusive per-cache lock prevents overlapping preparations.
$lock = [IO.File]::Open((Join-Path $cache 'prepare.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $files = @([pscustomobject]@{Source='codex.exe';Target='tran.exe';Hash=$sourceHash})
    foreach ($name in @($c.AuxiliaryFiles)) {
        if (!$name -or [IO.Path]::GetFileName([string]$name) -ne $name -or $name -notmatch '\.exe$' -or $name -in @('codex.exe','tran.exe')) {
            throw 'AuxiliaryFiles must contain distinct executable basenames, excluding codex.exe/tran.exe.'
        }
        if ($files.Target -contains $name) { throw 'Duplicate auxiliary filename.' }
        $path = Join-Path $resources $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required auxiliary file missing: $name" }
        $files += [pscustomobject]@{Source=$name;Target=$name;Hash=(Get-Hash $path)}
    }
    # Include every helper hash, not only the main binary, in the cache identity.
    $identity = ($files | ForEach-Object { "$($_.Target):$($_.Hash)" }) -join ';'
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $bundleHash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','') }
    finally { $sha.Dispose() }
    $destination = Join-Path $cache "$version-$bundleHash"
    if (!(Test-Path -LiteralPath $destination)) {
        $staging = Join-Path $cache ("staging-" + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        foreach ($file in $files) {
            $from = Join-Path $resources $file.Source
            $to = Join-Path $staging $file.Target
            Copy-Item -LiteralPath $from -Destination $to
            if ((Get-Hash $to) -ne $file.Hash -or (Get-Hash $from) -ne $file.Hash) {
                throw 'File changed during preparation; no new runtime selected.'
            }
        }
        Assert-Official (Join-Path $staging 'tran.exe')
        [IO.Directory]::Move($staging, $destination)
    }
    foreach ($file in $files) {
        if ((Get-Hash (Join-Path $destination $file.Target)) -ne $file.Hash) {
            throw 'Cached runtime integrity mismatch; refusing launch. Existing versions remain untouched.'
        }
    }
    Assert-Official (Join-Path $destination 'tran.exe')
    # Installed desktop and backend are always paired. Never silently run an old backend with a new desktop.
    if (!(Test-Path -LiteralPath $app) -or (Get-Hash $source) -ne $sourceHash) {
        throw 'Installed package changed during preparation; retry after update completes.'
    }
    $manifest = [ordered]@{Version=$version;PackageFullName=$package.PackageFullName;DesktopPath=$app;BackendPath=(Join-Path $destination 'tran.exe');Files=$files;PreparedAt=(Get-Date -Format o)}
    $manifestPath = Join-Path $cache 'current.json'
    $old = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    # Preserve the prior-version manifest across repeated launches of the same version.
    if (!$old -or $old.BackendPath -ne $manifest.BackendPath -or $old.DesktopPath -ne $manifest.DesktopPath) {
        Write-AtomicJson $manifest $manifestPath
    }
} finally { $lock.Dispose() }
if ($PrepareOnly) { [pscustomobject]@{Status='prepared-not-launched';Version=$version;BackendPath=$manifest.BackendPath}; return }
# Check again after preparation; never kill another instance that appeared meanwhile.
if (@(Get-Process -Name ChatGPT,codex,tran -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Another Codex instance appeared during preparation. No process was stopped.'
}


# Optional workstation gateway lifecycle. No effect on default/other profiles.
# Preparation never starts it; only the outer launch does, outside the MSIX job.
if (!$PackageWorker -and $c.PSObject.Properties['Gateway'] -and $c.Gateway.Enabled -eq $true) {
    $gateway = $c.Gateway
    $gatewayPath = [string]$gateway.ExecutablePath
    if (![IO.Path]::IsPathRooted($gatewayPath) -or !(Test-Path -LiteralPath $gatewayPath -PathType Leaf)) {
        throw 'Configured gateway executable does not exist at an absolute path.'
    }
    $gatewayPath = [IO.Path]::GetFullPath($gatewayPath)
    $port = [int]$gateway.Port
    if ($port -lt 1 -or $port -gt 65535) { throw 'Invalid gateway port.' }
    $timeout = 20
    if ($gateway.PSObject.Properties['TimeoutSeconds']) { $timeout = [int]$gateway.TimeoutSeconds }
    if ($timeout -lt 1 -or $timeout -gt 120) { throw 'Gateway timeout must be 1..120 seconds.' }
    $receipt = Join-Path $cache 'gateway-status.json'
    try {
        $existing = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.ExecutablePath -and [string]$_.ExecutablePath -ieq $gatewayPath
        })
        if (!$existing.Count) {
            $start = [Diagnostics.ProcessStartInfo]::new()
            $start.FileName = $gatewayPath
            $start.WorkingDirectory = Split-Path -Parent $gatewayPath
            $start.Arguments = 'tray'
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
            $null = [Diagnostics.Process]::Start($start)
        }
        $deadline = [DateTime]::UtcNow.AddSeconds($timeout)
        $ownerId = $null
        do {
            $listeners = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1') })
            foreach ($listener in $listeners) {
                $owner = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$listener.OwningProcess) -ErrorAction Stop
                if ($owner -and $owner.ExecutablePath -and [string]$owner.ExecutablePath -ieq $gatewayPath) {
                    $ownerId = [int]$listener.OwningProcess; break
                }
            }
            if ($null -ne $ownerId) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($null -eq $ownerId) { throw 'Expected gateway did not own its configured listening port before timeout.' }
        Write-AtomicJson ([ordered]@{Status='gateway-listening';ProcessId=$ownerId;Port=$port;Time=(Get-Date -Format o);ModelVerified=$false}) $receipt
    } catch {
        Write-AtomicJson ([ordered]@{Status='gateway-not-ready';Time=(Get-Date -Format o);Message=$_.Exception.Message}) $receipt
        throw
    }
}

# MSIX identity is required by native package/update APIs. Direct Process.Start from
# an unpackaged shell loses it. Enter the installed package before creating the app.
if (!$PackageWorker) {
    $null = Get-Command Invoke-CommandInDesktopPackage -ErrorAction Stop
    $appManifest = Get-AppxPackageManifest -Package $package.PackageFullName
    $entries = @($appManifest.Package.Applications.Application | Where-Object {
        ([string]$_.Executable).Replace('/','\') -ieq 'app\ChatGPT.exe'
    })
    if ($entries.Count -ne 1) { throw 'Cannot identify the installed desktop application entry.' }
    $quote = { param([string]$s) "'" + $s.Replace("'","''") + "'" }
    $command = '& ' + (& $quote $PSCommandPath) + ' -ConfigPath ' +
        (& $quote ([IO.Path]::GetFullPath($ConfigPath))) + ' -Mode ' +
        (& $quote $Mode) + ' -PackageWorker'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Environment is set by the worker below, since the package activation API
    # does not reliably inherit the calling shell's process environment.
    Invoke-CommandInDesktopPackage -PackageFamilyName $package.PackageFamilyName -AppId ([string]$entries[0].Id) -Command $shell -Args ("-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " + $encoded) -PreventBreakaway
    [pscustomobject]@{Status='package-launch-requested';Mode=$Mode;Version=$version}
    return
}
if (!('CompatibilityPackageIdentity' -as [type])) {
    Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CompatibilityPackageIdentity {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, StringBuilder name);
    public static string Read() {
        uint length=0;
        int result=GetCurrentPackageFullName(ref length,null);
        if(result!=122) throw new InvalidOperationException("No package identity: "+result);
        var value=new StringBuilder((int)length);
        result=GetCurrentPackageFullName(ref length,value);
        if(result!=0) throw new InvalidOperationException("Package identity failed: "+result);
        return value.ToString();
    }
}
'@
}
if ([CompatibilityPackageIdentity]::Read() -ne $package.PackageFullName) {
    throw 'Worker package identity does not match the selected installed package; refusing launch.'
}

$socket = [Net.Sockets.TcpClient]::new()
try {
    if (!$socket.ConnectAsync($proxy.DnsSafeHost,$proxy.Port).Wait(1500) -or !$socket.Connected) { throw 'Local proxy is not ready.' }
} finally { $socket.Dispose() }
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $app
$psi.WorkingDirectory = Split-Path -Parent $app
$psi.UseShellExecute = $false
$psi.Arguments = '--proxy-server="' + $c.ProxyUri + '" --proxy-bypass-list="' + $c.ProxyBypassList + '"'
foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) { $psi.EnvironmentVariables[$key] = [string]$c.ProxyUri }
$psi.EnvironmentVariables['NO_PROXY'] = [string]$c.NoProxy
$psi.EnvironmentVariables['NODE_USE_ENV_PROXY'] = '1'
$psi.EnvironmentVariables['CODEX_HOME'] = [string]$c.CodexHome
$psi.EnvironmentVariables.Remove('CODEX_APP_RUNTIME_CLI_PATH')
if ($Mode -eq 'Compatibility') { $psi.EnvironmentVariables['CODEX_CLI_PATH'] = $manifest.BackendPath }
else { $psi.EnvironmentVariables.Remove('CODEX_CLI_PATH') }
$p = [Diagnostics.Process]::Start($psi)
# This is a launch request, not proof of remote connection, model response, or performance.
[pscustomobject]@{Status='launch-requested';Mode=$Mode;Version=$version;ProcessId=$p.Id}
