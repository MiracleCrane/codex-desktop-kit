# Internal resolver for a stable backend dispatcher. Never starts the desktop.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$ProfilePath,
 [Parameter(Mandatory)][string]$ExpectedPackageFullName
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$ExpectedPackageFullName -or $ExpectedPackageFullName -match '[\r\n]') { throw 'Expected package identity is required.' }
# Identity must originate from the dispatcher's native GetCurrentPackageFullName.
# Do not substitute the highest installed version or accept a package from env.
$result = @(& (Join-Path $PSScriptRoot 'Launch-Compatibility.ps1') -ConfigPath $ProfilePath -PrepareOnly -ExpectedPackageFullName $ExpectedPackageFullName)
if ($result.Count -ne 1 -or $result[0].Status -ne 'prepared-not-launched' -or $result[0].PackageFullName -cne $ExpectedPackageFullName) { throw 'Unexpected resolver output.' }
[ordered]@{BackendPath=$result[0].BackendPath;PackageFullName=$result[0].PackageFullName;Version=$result[0].Version} | ConvertTo-Json -Compress
