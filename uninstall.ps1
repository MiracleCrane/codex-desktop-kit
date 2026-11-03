#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$InstallationPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts/Kit.Common.psm1') -Force
$r=Get-Content -LiteralPath $InstallationPath -Raw|ConvertFrom-Json
if($r.Product -ne 'codex-desktop-kit'){throw 'Unknown installation receipt.'}
$mutex=Enter-KitLock $r.CodexHome
try{
if(-not $PSCmdlet.ShouldProcess($r.Destination,'Remove kit integration and owned quota components, preserving rollback/runtime files')){return}
& (Join-Path $PSScriptRoot 'restore.ps1') -InstallationPath $InstallationPath -AllVersions -Confirm:$false
$current=$r
while($current){
    if($current.QuotaDestination){& (Join-Path $current.QuotaPackage 'uninstall.ps1') -Destination $current.QuotaDestination}
    if($current.PreviousReceipt){$current=Get-Content -LiteralPath $current.PreviousReceipt -Raw|ConvertFrom-Json}else{$current=$null}
}
Write-Output 'Kit integration uninstalled. Rollback records, downloaded packages and bridge runtimes remain for active sessions and recovery; no host was terminated.'
}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
