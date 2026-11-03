#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$InstallationPath,[switch]$AllVersions)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts/Kit.Common.psm1') -Force
$InstallationPath=Get-KitPhysicalPath $InstallationPath
$receipt=Get-Content -LiteralPath $InstallationPath -Raw|ConvertFrom-Json
if($receipt.Product -ne 'codex-desktop-kit'){throw 'Unknown installation receipt.'}
$mutex=Enter-KitLock $receipt.CodexHome
try{
$restoredNow=$false
if(-not $PSCmdlet.ShouldProcess($receipt.Destination,'Restore owned proxy block, bridge URL and shortcuts')){return}
if($receipt.Status -ne 'restored'){
    foreach($entry in $receipt.Shortcuts){
        if(Test-Path -LiteralPath $entry.Path){$hash=Get-KitHash $entry.Path;if($hash -notin @($entry.InstalledHash,$entry.BeforeHash)){throw 'Shortcut changed independently; preserve it for review.'}}
        elseif($entry.BeforeHash){throw 'An original shortcut was removed independently.'}
        if($entry.Backup -and (Get-KitHash $entry.Backup) -ne $entry.BeforeHash){throw 'Original shortcut backup changed.'}
    }
    & $receipt.PythonPath -X utf8 (Join-Path $receipt.PackageRoot 'scripts/env-edit.py') check-restore --state $receipt.EnvState
    if($LASTEXITCODE -ne 0){throw 'Proxy block restore preflight failed; no configuration was changed.'}
    if($receipt.BridgeReceipt){& (Join-Path $receipt.BridgePackage 'scripts/Restore-Bridge.ps1') -InstallationPath $receipt.BridgeReceipt -WhatIf}
    if($receipt.BridgeReceipt){& (Join-Path $receipt.BridgePackage 'scripts/Restore-Bridge.ps1') -InstallationPath $receipt.BridgeReceipt -Confirm:$false}
    & $receipt.PythonPath -X utf8 (Join-Path $receipt.PackageRoot 'scripts/env-edit.py') restore --state $receipt.EnvState
    if($LASTEXITCODE -ne 0){throw 'Proxy block changed; no unknown configuration was overwritten.'}
    foreach($entry in $receipt.Shortcuts){
        if((Test-Path -LiteralPath $entry.Path) -and (Get-KitHash $entry.Path) -eq $entry.InstalledHash){
            if($entry.Backup){Set-KitFile $entry.Path $entry.Backup $entry.InstalledHash}
            else{Remove-Item -LiteralPath $entry.Path}
        }
    }
    $receipt.Status='restored';Write-KitJson $InstallationPath $receipt
    $restoredNow=$true
}
if($AllVersions -and $receipt.PreviousReceipt){& $PSCommandPath -InstallationPath $receipt.PreviousReceipt -AllVersions -Confirm:$false}
if($restoredNow -and -not $AllVersions -and $receipt.PreviousReceipt -and
    $InstallationPath -eq (Join-Path $receipt.Destination 'installation.json')){
    $archive=Join-Path (Split-Path -Parent $receipt.EnvState) 'restored-installation.json'
    Write-KitJson $archive $receipt
    $previous=Get-Content -LiteralPath $receipt.PreviousReceipt -Raw|ConvertFrom-Json
    if($previous.Status -ne 'enabled'){throw 'Previous receipt is not enabled; restored files were preserved for review.'}
    Write-KitJson $InstallationPath $previous
}
Write-Output 'Owned integration restored. Active hosts and unknown files were preserved.'
}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
