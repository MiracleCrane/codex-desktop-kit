#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationPath,[Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
$r=Get-Content -LiteralPath $InstallationPath -Raw|ConvertFrom-Json
if($r.Product -ne 'codex-desktop-kit' -or $r.Status -ne 'enabled'){throw 'An enabled kit installation is required.'}
$arguments=@{Destination=$r.Destination;ProxyUri=$r.ProxyUri;CodexHome=$r.CodexHome;PythonPath=$r.PythonPath;WithBridge=[bool]$r.BridgeReceipt;WithQuotaOrb=[bool]$r.QuotaDestination;ShortcutPath=@($r.Shortcuts|Where-Object {-not $_.PSObject.Properties['Kind'] -or $_.Kind -eq 'codex'}|ForEach-Object Path);NoShortcuts=(@($r.Shortcuts).Count -eq 0)}
if($r.PSObject.Properties['NoQuotaShortcut']){$arguments.NoQuotaShortcut=[bool]$r.NoQuotaShortcut}
if($r.NodePath){$arguments.NodePath=$r.NodePath}
if($r.PSObject.Properties['MagpiePath'] -and $r.MagpiePath){$arguments.MagpiePath=$r.MagpiePath;$arguments.MagpieBaseUrl=$r.MagpieBaseUrl}
& (Join-Path ([IO.Path]::GetFullPath($PackageDirectory)) 'install.ps1') @arguments
