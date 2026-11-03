#Requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$WorkDirectory,[Parameter(Mandatory)][string]$ProxyUri,[Parameter(Mandatory)][string]$PythonPath,[string]$NodePath,[switch]$WithComponents)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts/Kit.Common.psm1') -Force
if(Test-Path -LiteralPath $WorkDirectory){throw 'Use a fresh external test directory.'}
New-Item -ItemType Directory -Path $WorkDirectory|Out-Null
$codex=Join-Path $WorkDirectory 'home';New-Item -ItemType Directory -Path $codex|Out-Null
$envFile=Join-Path $codex '.env';$config=Join-Path $codex 'config.toml'
[IO.File]::WriteAllText($envFile,"no_proxy=corp.internal`nUNRELATED=original`n")
[IO.File]::WriteAllText($config,"model = `"fixture-model`"`n")
$linkPath=Join-Path $WorkDirectory 'original.lnk'
$link=(New-Object -ComObject WScript.Shell).CreateShortcut($linkPath)
$link.TargetPath=Join-Path $WorkDirectory 'lzc-original-fixture.exe';$link.Arguments='--preserved';$link.WorkingDirectory=$WorkDirectory;$link.Save()
$originalHash=Get-KitHash $linkPath
$destination=Join-Path $WorkDirectory 'installed';$receiptPath=Join-Path $destination 'installation.json'
$args=@{Destination=$destination;ProxyUri=$ProxyUri;CodexHome=$codex;PythonPath=$PythonPath;ShortcutPath=@($linkPath);WithBridge=[bool]$WithComponents;WithQuotaOrb=[bool]$WithComponents}
if($NodePath){$args.NodePath=$NodePath}
try{
    & (Join-Path $root 'install.ps1') @args
    $first=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if((Get-KitShortcut $linkPath).Target -ne $first.Launcher){throw 'Kit is not the direct shortcut owner.'}
    if($WithComponents){$manual=Get-KitShortcut (Join-Path $WorkDirectory 'Quota Orb.lnk');if(-not $manual -or $manual.Arguments -notmatch '--toggle-orb$'){throw 'Manual quota toggle is missing.'}}
    if((Get-Content -LiteralPath $envFile -Raw) -notmatch 'corp.internal'){throw 'Intranet bypass lost.'}
    & (Join-Path $root 'update.ps1') -InstallationPath $receiptPath -PackageDirectory $root
    $second=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    $beforeEnv=[IO.File]::ReadAllBytes($envFile)
    [IO.File]::WriteAllText($envFile,([Text.Encoding]::UTF8.GetString($beforeEnv).Replace('NODE_USE_ENV_PROXY="1"','NODE_USE_ENV_PROXY="0"')))
    $beforeConfig=Get-KitHash $config;$beforeLink=Get-KitHash $linkPath;$beforeReceipt=Get-KitHash $receiptPath
    $rejected=$false;try{& (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -Confirm:$false}catch{$rejected=$true}
    if(-not $rejected -or (Get-KitHash $config) -ne $beforeConfig -or (Get-KitHash $linkPath) -ne $beforeLink -or (Get-KitHash $receiptPath) -ne $beforeReceipt){throw 'Conflicting proxy block caused a partial restore.'}
    [IO.File]::WriteAllBytes($envFile,$beforeEnv)
    if($WithComponents){
        $removal=@{};foreach($key in $args.Keys){$removal[$key]=$args[$key]};$removal.WithBridge=$false
        $rejected=$false;try{& (Join-Path $root 'install.ps1') @removal}catch{$rejected=$true}
        if(-not $rejected -or (Get-KitHash $config) -ne $beforeConfig -or (Get-KitHash $linkPath) -ne $beforeLink){throw 'Removing bridge selection left a stale local route.'}
    }
    & (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -Confirm:$false
    $active=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if($active.Status -ne 'enabled' -or $active.InstanceId -ne $first.InstanceId){throw 'Single rollback did not restore the active receipt.'}
    & (Join-Path $root 'update.ps1') -InstallationPath $receiptPath -PackageDirectory $root
    [IO.File]::AppendAllText($envFile,"LATER=preserved`n")
    [IO.File]::AppendAllText($config,"model_verbosity = `"low`"`n")
    & (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -AllVersions -Confirm:$false
    if((Get-KitHash $linkPath) -ne $originalHash){throw 'Original shortcut was not restored byte-for-byte.'}
    if($WithComponents -and (Test-Path -LiteralPath (Join-Path $WorkDirectory 'Quota Orb.lnk'))){throw 'Created manual quota shortcut was not removed.'}
    $text=Get-Content -LiteralPath $envFile -Raw
    if($text -match 'codex-desktop-kit' -or $text -notmatch 'LATER=preserved' -or $text -notmatch 'no_proxy=corp.internal'){throw 'Environment restore lost later edits or bypasses.'}
    $text=Get-Content -LiteralPath $config -Raw
    if($text -match 'openai_base_url' -or $text -notmatch 'model_verbosity'){throw 'Model route restore lost unrelated configuration.'}
    $files=@(Get-ChildItem -LiteralPath (Join-Path $destination 'instances') -Recurse -File|Where-Object {$_.Name -match 'installation\.json$|transaction\.json$'}|ForEach-Object {@{Path=$_.FullName;Hash=(Get-KitHash $_.FullName)}})
    $rootHash=Get-KitHash $receiptPath
    & (Join-Path $root 'restore.ps1') -InstallationPath $receiptPath -WhatIf
    if((Get-KitHash $receiptPath) -ne $rootHash){throw 'WhatIf modified the restored root receipt.'}
    foreach($file in $files){if((Get-KitHash $file.Path) -ne $file.Hash){throw 'WhatIf modified restoration metadata.'}}
    & (Join-Path $root 'uninstall.ps1') -InstallationPath $receiptPath -Confirm:$false
    Write-Output 'Installation, upgrade, conflict preflight, rollback pointer, re-upgrade and full restore passed. No model requests or desktop activation were sent.'
}finally{
    # Fixture-only cleanup: stop exactly the supervisors created below this external test root.
    if(Test-Path -LiteralPath (Join-Path $destination 'instances')){
        Get-ChildItem -LiteralPath (Join-Path $destination 'instances') -Recurse -Filter installation.json -File|ForEach-Object {
            $r=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
            if($r.PSObject.Properties['SupervisorPath'] -and $r.SupervisorPath.StartsWith($WorkDirectory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
                Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $r.SupervisorPath}|ForEach-Object {Stop-Process -Id $_.ProcessId}
            }
        }
    }
}
