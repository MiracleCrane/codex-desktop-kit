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
$magpie=$null
if($r.PSObject.Properties['MagpiePath'] -and $r.MagpiePath){
    $matchText=& $r.PythonPath -X utf8 (Join-Path $r.PackageRoot 'scripts/inspect-route.py') --config (Join-Path $r.CodexHome 'config.toml') --expected-base-url $r.MagpieBaseUrl
    if($LASTEXITCODE -ne 0){throw 'Magpie route validation failed.'}
    $match=$matchText|ConvertFrom-Json
    $gatewayReady=$false
    try{$health=Invoke-RestMethod -Uri (([uri]$r.MagpieBaseUrl).GetLeftPart([UriPartial]::Authority)+'/api/hello') -NoProxy -TimeoutSec 2;$gatewayReady=$health.name -eq 'magpie' -and [bool]$health.version}catch{}
    $magpie=[pscustomobject]@{ExecutableExists=(Test-Path -LiteralPath $r.MagpiePath -PathType Leaf);RouteMatches=$match.matchesExpected;CatalogExists=$match.catalogExists;GatewayReady=$gatewayReady}
    $settings=Get-Content -Raw -LiteralPath $r.LaunchConfig|ConvertFrom-Json
    $reconnect=$r.PSObject.Properties['ReconnectMagpie'] -and [bool]$r.ReconnectMagpie
    if([bool]$settings.Magpie.ReconnectOnLaunch -ne [bool]$reconnect -or ($reconnect -and -not(Test-Path -LiteralPath $settings.Magpie.ReconnectScript))){throw 'Magpie reconnect settings differ from the receipt.'}
    if($r.BridgeReceipt -or $settings.Bridge -or -not $settings.Magpie -or $settings.Magpie.BaseUrl -ne $r.MagpieBaseUrl -or $settings.Magpie.ExecutablePath -ne $r.MagpiePath){throw 'Magpie mode conflicts with the installed launch configuration.'}
}
$shortcuts=@($r.Shortcuts|ForEach-Object {$actual=Get-KitShortcut $_.Path;[pscustomobject]@{Path=$_.Path;Matches=($null -ne $actual -and $actual.Hash -eq $_.InstalledHash)}})
$launcherMatches=(Get-KitHash $r.Launcher) -eq $r.LauncherHash
$proxyReady=$true;try{Assert-KitProxy $r.ProxyUri}catch{$proxyReady=$false}
$bridge=$null
if($r.BridgeReceipt){$bridge=(& (Join-Path $r.BridgePackage 'scripts/Test-Bridge.ps1') -InstallationPath $r.BridgeReceipt)|ConvertFrom-Json}
$orb=$null
if($r.QuotaDestination){$orb=(& (Join-Path $r.QuotaPackage 'Get-QuotaOrb.ps1') -Destination $r.QuotaDestination)|ConvertFrom-Json}
[pscustomobject]@{Version=$r.Version;Status=$r.Status;ProxyReady=$proxyReady;LauncherMatches=$launcherMatches;ProxyBlockOwned=$environment.ownsBlock;NativeProxyEffective=$environment.effective;ModelRoute=$route;Shortcuts=$shortcuts;Bridge=$bridge;Magpie=$magpie;QuotaOrb=$orb;ColdRestartVerified=$r.ColdRestartVerified;SystemProxyTunOffVerified=$r.SystemProxyTunOffVerified;Note='Static checks do not prove a fresh desktop model/tool request. Browser and MCP helpers require their own supported proxy settings.'}|ConvertTo-Json -Depth 10
if($r.Status -eq 'enabled' -and (-not $launcherMatches -or -not $environment.effective -or @($shortcuts|Where-Object {-not $_.Matches}).Count -gt 0)){throw 'Installed configuration differs from its receipt.'}
if($magpie -and (-not $magpie.ExecutableExists -or -not $magpie.RouteMatches -or -not $magpie.CatalogExists)){throw 'Magpie configuration is incomplete or changed independently.'}
if(-not $r.BridgeReceipt -and -not $magpie -and $route.route -eq 'local-override'){throw 'An external local model endpoint is configured but not managed by this kit.'}
