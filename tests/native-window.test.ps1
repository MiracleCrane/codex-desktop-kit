#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory,[int]$DelayMilliseconds=58000,[string]$ProbeAumid)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $WorkDirectory){throw 'Use a fresh external fixture directory.'}
New-Item -ItemType Directory -Path $WorkDirectory|Out-Null
$root=Split-Path -Parent $PSScriptRoot
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$exe=Join-Path $WorkDirectory 'lzc-native-window-fixture.exe'
& $compiler /nologo /target:exe /optimize+ /codepage:65001 "/out:$exe" (Join-Path $root 'src/CompanionStartup.cs') (Join-Path $root 'src/NativeHostWindows.cs') (Join-Path $PSScriptRoot 'NativeWindowFixtureTests.cs')
if($LASTEXITCODE -ne 0){throw 'Native fixture compilation failed.'}
if($ProbeAumid){& $exe --live-probe $ProbeAumid}else{& $exe $DelayMilliseconds}
if($LASTEXITCODE -ne 0){throw 'Native window fixture failed.'}
