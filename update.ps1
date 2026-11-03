#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallationPath,[Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference='Stop'
$r=Get-Content -LiteralPath $InstallationPath -Raw|ConvertFrom-Json
if($r.Product -ne 'codex-desktop-kit' -or $r.Status -ne 'enabled'){throw 'An enabled kit installation is required.'}
$arguments=@{Destination=$r.Destination;ProxyUri=$r.ProxyUri;CodexHome=$r.CodexHome;PythonPath=$r.PythonPath;WithBridge=[bool]$r.BridgeReceipt;WithQuotaOrb=[bool]$r.QuotaDestination;ShortcutPath=@($r.Shortcuts|ForEach-Object Path);NoShortcuts=(@($r.Shortcuts).Count -eq 0)}
if($r.NodePath){$arguments.NodePath=$r.NodePath}
& (Join-Path ([IO.Path]::GetFullPath($PackageDirectory)) 'install.ps1') @arguments
