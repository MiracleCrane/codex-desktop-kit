#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,[switch]$Test)
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($output.StartsWith($PSScriptRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Build output must be outside the repository.'}
New-Item -ItemType Directory -Path $output -Force|Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.cs' -File|ForEach-Object FullName)
& $compiler /nologo /target:winexe /optimize+ /codepage:65001 /reference:System.Web.Extensions.dll /reference:System.Windows.Forms.dll "/out:$(Join-Path $output 'CodexDesktopKit.exe')" @sources
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed.'}
if($Test){
    & $compiler /nologo /target:exe /optimize+ /codepage:65001 "/out:$(Join-Path $output 'LaunchTests.exe')" (Join-Path $PSScriptRoot 'src/LaunchPlan.cs') (Join-Path $PSScriptRoot 'tests/LaunchTests.cs')
    if($LASTEXITCODE -ne 0){throw 'Test compilation failed.'}
    & (Join-Path $output 'LaunchTests.exe')
    if($LASTEXITCODE -ne 0){throw 'Launch behavior tests failed.'}
    & $compiler /nologo /target:exe /optimize+ /codepage:65001 "/out:$(Join-Path $output 'CompanionStartupTests.exe')" (Join-Path $PSScriptRoot 'src/CompanionStartup.cs') (Join-Path $PSScriptRoot 'tests/CompanionStartupTests.cs')
    if($LASTEXITCODE -ne 0){throw 'Readiness test compilation failed.'}
    & (Join-Path $output 'CompanionStartupTests.exe')
    if($LASTEXITCODE -ne 0){throw 'Companion readiness tests failed.'}
}
[pscustomobject]@{Launcher=(Join-Path $output 'CodexDesktopKit.exe');SHA256=(Get-FileHash -LiteralPath (Join-Path $output 'CodexDesktopKit.exe')).Hash}
