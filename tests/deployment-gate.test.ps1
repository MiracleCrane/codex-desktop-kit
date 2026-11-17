$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Wait-CodexPackageReady.ps1')
function Check-Failure($Action,$Pattern) { try { & $Action | Out-Null } catch { if($_.Exception.Message -match $Pattern){return};throw };throw "Expected: $Pattern" }
$global:gateReads=0
Check-Failure { Get-CodexReadyPackage -ReadStatus { $global:gateReads++; [pscustomobject]@{Ready=$false;PackageFullName='old'} } } 'updating'
if($global:gateReads -ne 1){throw 'Busy gate polled instead of returning immediately'}
Check-Failure { Get-CodexReadyPackage -ReadStatus { throw 'query unavailable' } } 'Unable to read'
Check-Failure { Get-CodexReadyPackage -ReadStatus { $null } } 'not ready'
Check-Failure { Get-CodexReadyPackage -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName=$null} } } 'not ready'
$r=Get-CodexReadyPackage -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName='new'} }
if($r.PackageFullName -ne 'new'){throw 'New ready package rejected'}
Check-Failure { Assert-CodexPackageReady -ExpectedPackageFullName 'old' -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName='new'} } } 'changed'
Check-Failure { Assert-CodexPackageReady -ExpectedPackageFullName 'old' -ReadStatus { [pscustomobject]@{Ready=$false;PackageFullName='old'} } } 'not ready'
$r=Assert-CodexPackageReady -ExpectedPackageFullName 'new' -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName='new'} }
if($r.PackageFullName -ne 'new'){throw 'Ready assertion failed'}
'PASS: busy rejection after one read, query failure, missing/unknown status, ready new package, final version mismatch, final busy rejection, final ready acceptance. No polling or application startup.'
