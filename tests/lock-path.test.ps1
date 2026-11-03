#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $WorkDirectory){throw 'Use a fresh external test directory.'}
New-Item -ItemType Directory -Path $WorkDirectory|Out-Null
$root=Split-Path -Parent $PSScriptRoot
$module=Join-Path $root 'scripts/Kit.Common.psm1'
Import-Module $module -Force
$inside=Join-Path $WorkDirectory 'inside';$outside=Join-Path $WorkDirectory 'outside'
New-Item -ItemType Directory -Path $inside,$outside|Out-Null
New-Item -ItemType Junction -Path (Join-Path $inside 'downloads') -Target $outside|Out-Null
$blocked=$false;try{$null=Get-KitChildPath $inside (Join-Path $inside 'downloads/archive.zip')}catch{$blocked=$true}
if(-not $blocked -or (Get-ChildItem -LiteralPath $outside -Force).Count -ne 0){throw 'Managed output escaped through a junction.'}
$script=Join-Path $WorkDirectory 'hold-lock.ps1';$ready=Join-Path $WorkDirectory 'ready';$codex=Join-Path $WorkDirectory 'home'
[IO.File]::WriteAllText($script,@'
param([string]$Module,[string]$CodexHome,[string]$Ready)
Import-Module $Module -Force
$lock=Enter-KitLock $CodexHome
try{[IO.File]::WriteAllText($Ready,'ready');Start-Sleep -Seconds 4}finally{$lock.ReleaseMutex();$lock.Dispose()}
'@)
$arguments=@('-NoProfile','-File',('"'+$script+'"'),'-Module',('"'+$module+'"'),'-CodexHome',('"'+$codex+'"'),'-Ready',('"'+$ready+'"'))
$process=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -WindowStyle Hidden -PassThru
try{
    $deadline=[DateTime]::UtcNow.AddSeconds(8)
    while(-not(Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path -LiteralPath $ready)){throw 'Fixture lock was not acquired.'}
    $blocked=$false;$lock=$null
    try{$lock=Enter-KitLock $codex}catch{$blocked=$true}finally{if($lock){$lock.ReleaseMutex();$lock.Dispose()}}
    if(-not $blocked){throw 'Concurrent process acquired the installation lock.'}
    if(-not $process.WaitForExit(6000)){throw 'Fixture lock owner did not exit.'}
    $lock=Enter-KitLock $codex;$lock.ReleaseMutex();$lock.Dispose()
}finally{if(-not $process.HasExited){Stop-Process -Id $process.Id};$process.Dispose()}
Write-Output 'Physical child paths and cross-process installation exclusion passed.'
