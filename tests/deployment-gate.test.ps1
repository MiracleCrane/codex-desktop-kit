$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Wait-CodexPackageReady.ps1')
function Check-Failure($Action,$Pattern) { try { & $Action | Out-Null } catch { if($_.Exception.Message -match $Pattern){return};throw };throw "Expected: $Pattern" }
$global:gateQueue=@(
 [pscustomobject]@{Ready=$false;PackageFullName='old'},
 [pscustomobject]@{Ready=$true;PackageFullName='old'},
 [pscustomobject]@{Ready=$true;PackageFullName='new'},
 [pscustomobject]@{Ready=$true;PackageFullName='new'}
)
$global:gateIndex=0
$r=Wait-CodexPackageReady -TimeoutSeconds 2 -PollMilliseconds 1 -StableSamples 2 -ReadStatus { $s=$global:gateQueue[$global:gateIndex];$global:gateIndex++;$s }
if($r.PackageFullName -ne 'new' -or $global:gateIndex -ne 4){throw 'Readiness/change reset failed'}
Check-Failure { Wait-CodexPackageReady -TimeoutSeconds 1 -PollMilliseconds 10 -ReadStatus { [pscustomobject]@{Ready=$false;PackageFullName=$null} } } 'timed out'
Check-Failure { Wait-CodexPackageReady -ReadStatus { throw 'query unavailable' } } 'Unable to read'
Check-Failure { Wait-CodexPackageReady -ReadStatus { $null } } 'Unknown'
Check-Failure { Assert-CodexPackageReady -ExpectedPackageFullName 'old' -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName='new'} } } 'changed'
Check-Failure { Assert-CodexPackageReady -ExpectedPackageFullName 'old' -ReadStatus { [pscustomobject]@{Ready=$false;PackageFullName='old'} } } 'not ready'
$r=Assert-CodexPackageReady -ExpectedPackageFullName 'new' -ReadStatus { [pscustomobject]@{Ready=$true;PackageFullName='new'} }
if($r.PackageFullName -ne 'new'){throw 'Ready assertion failed'}
'PASS: readiness transition, package-change stability reset, timeout, query failure, unknown status, final version mismatch, final busy rejection, final ready acceptance. No application started.'
