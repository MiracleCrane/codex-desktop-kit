#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts/Kit.Common.psm1') -Force
$r=Get-Content -LiteralPath $InstallationPath -Raw|ConvertFrom-Json
if($r.Product -ne 'codex-desktop-kit'){throw 'Unknown installation receipt.'}
$envState=& $r.PythonPath -X utf8 (Join-Path $r.PackageRoot 'scripts/env-edit.py') inspect --state $r.EnvState
if($LASTEXITCODE -ne 0){throw 'Proxy block inspection failed.'}
$environment=$envState|ConvertFrom-Json
$routeText=& $r.PythonPath -X utf8 (Join-Path $r.PackageRoot 'scripts/inspect-route.py') --config (Join-Path $r.CodexHome 'config.toml')
if($LASTEXITCODE -ne 0){throw 'Model route inspection failed.'}
$route=$routeText|ConvertFrom-Json
$shortcuts=@($r.Shortcuts|ForEach-Object {$actual=Get-KitShortcut $_.Path;[pscustomobject]@{Path=$_.Path;Matches=($null -ne $actual -and $actual.Hash -eq $_.InstalledHash)}})
$launcherMatches=(Get-KitHash $r.Launcher) -eq $r.LauncherHash
$proxyReady=$true;try{Assert-KitProxy $r.ProxyUri}catch{$proxyReady=$false}
$bridge=$null
if($r.BridgeReceipt){$bridge=(& (Join-Path $r.BridgePackage 'scripts/Test-Bridge.ps1') -InstallationPath $r.BridgeReceipt)|ConvertFrom-Json}
$orb=$null
if($r.QuotaDestination){$orb=(& (Join-Path $r.QuotaPackage 'Get-QuotaOrb.ps1') -Destination $r.QuotaDestination)|ConvertFrom-Json}
[pscustomobject]@{Version=$r.Version;Status=$r.Status;ProxyReady=$proxyReady;LauncherMatches=$launcherMatches;ProxyBlockOwned=$environment.ownsBlock;NativeProxyEffective=$environment.effective;ModelRoute=$route;Shortcuts=$shortcuts;Bridge=$bridge;QuotaOrb=$orb;ColdRestartVerified=$r.ColdRestartVerified;SystemProxyTunOffVerified=$r.SystemProxyTunOffVerified;Note='Static checks do not prove a fresh desktop model/tool request. Browser and MCP helpers require their own supported proxy settings.'}|ConvertTo-Json -Depth 10
if($r.Status -eq 'enabled' -and (-not $launcherMatches -or -not $environment.effective -or @($shortcuts|Where-Object {-not $_.Matches}).Count -gt 0)){throw 'Installed configuration differs from its receipt.'}
if(-not $r.BridgeReceipt -and $route.route -eq 'local-override'){throw 'An external local model endpoint is configured but not managed by this kit.'}
