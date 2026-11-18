#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory,[Parameter(Mandatory)][string]$ProxyUri,[Parameter(Mandatory)][string]$PythonPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts/Kit.Common.psm1') -Force
if(Test-Path -LiteralPath $WorkDirectory){throw 'Use a fresh external test directory.'}
New-Item -ItemType Directory -Path $WorkDirectory|Out-Null
$codex=Join-Path $WorkDirectory 'home';New-Item -ItemType Directory -Path $codex|Out-Null
$config=Join-Path $codex 'config.toml'
[IO.File]::WriteAllText($config,"model = `"fixture-model`"`n")
$linkPath=Join-Path $WorkDirectory 'original.lnk'
$link=(New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
$link.TargetPath=Join-Path $WorkDirectory 'original.exe';$link.Arguments='--preserved';$link.Save()
$originalHash=Get-KitHash $linkPath
$destination=Join-Path $WorkDirectory 'installed';$receiptPath=Join-Path $destination 'installation.json'
$arguments=@{Destination=$destination;ProxyUri=$ProxyUri;CodexHome=$codex;PythonPath=$PythonPath;ShortcutPath=@($linkPath)}
& (Join-Path $root 'install.ps1') @arguments | Out-Null
& (Join-Path $root 'update.ps1') -InstallationPath $receiptPath -PackageDirectory $root | Out-Null
$base='http://127.0.0.1:34567/backend-api/codex'
[IO.File]::AppendAllText($config,"openai_base_url = `"$base`"`nmodel_catalog_json = `"models.json`"`n")
[IO.File]::WriteAllText((Join-Path $codex 'models.json'),'{}')
$modelHash=Get-KitHash $config
& (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -AllVersions -Confirm:$false | Out-Null
if((Get-KitHash $config)-ne $modelHash -or (Get-KitHash $linkPath)-ne $originalHash){throw 'Full restore changed the externally owned model route or original shortcut.'}
$fixtureSource=Join-Path $WorkDirectory 'fixture.cs'
[IO.File]::WriteAllText($fixtureSource,'class Fixture { static void Main() {} }')
$magpie=Join-Path $WorkDirectory 'lzc-magpie-fixture.exe'
& (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe') /nologo /target:winexe "/out:$magpie" $fixtureSource
if($LASTEXITCODE -ne 0){throw 'Fixture compilation failed.'}
$arguments.MagpiePath=$magpie;$arguments.MagpieBaseUrl=$base;$arguments.ReconnectMagpie=$true
$rejected=$false;try{& (Join-Path $root 'install.ps1') @arguments -WithBridge|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Conflicting gateway owners were accepted.'}
& (Join-Path $root 'install.ps1') @arguments | Out-Null
$first=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json
if($first.BridgeReceipt -or $first.MagpieBaseUrl-ne $base -or (Get-KitHash $config)-ne $modelHash){throw 'Magpie install changed model configuration or selected bridge.'}
& (Join-Path $root 'update.ps1') -InstallationPath $receiptPath -PackageDirectory $root | Out-Null
$updated=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json
if($updated.BridgeReceipt -or $updated.MagpiePath-ne $magpie -or $updated.MagpieBaseUrl-ne $base -or -not $updated.ReconnectMagpie){throw 'Update did not preserve Magpie mode.'}
$launch=Get-Content -Raw -LiteralPath $updated.LaunchConfig|ConvertFrom-Json
if($launch.Bridge -or $launch.Magpie.ExecutablePath-ne $magpie){throw 'Launcher still depends on the bridge.'}
$receiptHash=Get-KitHash $receiptPath;$linkHash=Get-KitHash $linkPath
$originalConfig=[IO.File]::ReadAllText($config)
[IO.File]::WriteAllText($config,$originalConfig.Replace('34567','34568'))
$changedHash=Get-KitHash $config
$rejected=$false;try{& (Join-Path $root 'update.ps1') -InstallationPath $receiptPath -PackageDirectory $root|Out-Null}catch{$rejected=$true}
if(-not $rejected -or (Get-KitHash $receiptPath)-ne $receiptHash -or (Get-KitHash $linkPath)-ne $linkHash -or (Get-KitHash $config)-ne $changedHash){throw 'Changed model route was overwritten or partly installed.'}
[IO.File]::WriteAllText($config,$originalConfig)
& (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -AllVersions -Confirm:$false | Out-Null
if((Get-KitHash $config)-ne $modelHash -or (Get-KitHash $linkPath)-ne $originalHash){throw 'Magpie restore did not preserve its external route.'}
Write-Output 'Magpie migration, original shortcut preservation, update, owner conflict and restore passed. No model requests, gateway processes or Codex activation were sent.'
