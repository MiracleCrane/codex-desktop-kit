#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Destination=(Join-Path $env:LOCALAPPDATA 'Programs/CodexDesktopKit'),
    [string]$ProxyUri,
    [string]$CodexHome=$(if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $HOME '.codex'}),
    [string]$NoProxy=$env:NO_PROXY,
    [switch]$WithBridge,
    [switch]$WithQuotaOrb,
    [string[]]$ShortcutPath=@(),
    [switch]$NoShortcuts,
    [switch]$NoQuotaShortcut,
    [string]$NodePath,
    [string]$PythonPath,
    [switch]$Launch
)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This package targets Windows Codex Desktop.'}
Import-Module (Join-Path $PSScriptRoot 'scripts/Kit.Common.psm1') -Force
if(-not $ProxyUri){
    $answer=Read-Host '本地 HTTP/mixed 代理端口或 URI（回车使用 7897）'
    if(-not $answer){$answer='7897'}
    $ProxyUri=if($answer -match '^\d+$'){"http://127.0.0.1:$answer"}else{$answer}
    if(-not $WithQuotaOrb){$WithQuotaOrb=(Read-Host '安装额度悬浮球？y/N') -match '^(y|yes)$'}
    if(-not $WithBridge){$WithBridge=(Read-Host '安装可选传输桥接？y/N') -match '^(y|yes)$'}
}
$ProxyUri=$ProxyUri.TrimEnd('/')
Assert-KitProxy $ProxyUri
if($NoShortcuts -and $ShortcutPath.Count -gt 0){throw 'NoShortcuts and ShortcutPath cannot be combined.'}
$CodexHome=Get-KitPhysicalPath $CodexHome
$Destination=Assert-KitDestination $Destination $CodexHome
$codex=Get-KitCodex
$PythonPath=Resolve-KitExecutable $PythonPath 'python.exe'
& $PythonPath -I -c 'import sys;sys.exit(0 if sys.version_info >= (3,11) else 1)'
if($LASTEXITCODE -ne 0){throw 'Python 3.11 or newer is required.'}
$routeText=& $PythonPath -X utf8 (Join-Path $PSScriptRoot 'scripts/inspect-route.py') --config (Join-Path $CodexHome 'config.toml')
if($LASTEXITCODE -ne 0){throw 'Existing Codex configuration could not be inspected.'}
$route=$routeText|ConvertFrom-Json
if(-not $WithBridge -and $route.route -eq 'local-override'){
    throw 'Codex already uses a local model endpoint. Restore its owning installation first, or select bridge integration; a proxy-only shortcut cannot start that external service.'
}
$powerShellPath=(Get-Process -Id $PID).Path
$metadata=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'kit.json') -Raw|ConvertFrom-Json
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'components.json') -Raw|ConvertFrom-Json
$mutex=Enter-KitLock $CodexHome
$receipt=$null;$receiptPath=Join-Path $Destination 'installation.json'
try{
    New-Item -ItemType Directory -Path $Destination -Force|Out-Null
    $instance=[guid]::NewGuid().ToString()
    $instanceRoot=Get-KitChildPath $Destination (Join-Path $Destination ('instances/'+$instance))
    New-Item -ItemType Directory -Path $instanceRoot|Out-Null
    $previous=$null;$previousPath=$null
    if(Test-Path -LiteralPath $receiptPath){
        $previous=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
        if($previous.Product -ne 'codex-desktop-kit' -or $previous.CodexHome -ne $CodexHome){throw 'Existing receipt belongs to another installation.'}
        if($previous.Status -notin @('enabled','restored')){throw 'Previous installation needs restore/recovery before another install.'}
        if($previous.Status -eq 'enabled'){
            if([bool]$previous.BridgeReceipt -ne [bool]$WithBridge -or [bool]$previous.QuotaDestination -ne [bool]$WithQuotaOrb){
                throw 'Changing component selection requires uninstall/restore of the existing integration first. Updates preserve the selected components.'
            }
            if($NoShortcuts -and @($previous.Shortcuts).Count -gt 0){throw 'Restore the existing shortcuts before switching to NoShortcuts.'}
            if($previous.PSObject.Properties['NoQuotaShortcut'] -and [bool]$previous.NoQuotaShortcut -ne [bool]$NoQuotaShortcut){throw 'Restore the existing integration before changing manual shortcut selection.'}
            $previousCodexEntries=@($previous.Shortcuts|Where-Object {-not $_.PSObject.Properties['Kind'] -or $_.Kind -eq 'codex'})
            if($ShortcutPath.Count -gt 0 -and $previousCodexEntries.Count -gt 0){
                $requested=@($ShortcutPath|ForEach-Object {Get-KitPhysicalPath $_}|Sort-Object)
                $existing=@($previousCodexEntries|ForEach-Object Path|Sort-Object)
                if(($requested -join "`n") -ne ($existing -join "`n")){throw 'Restore the existing integration before selecting different shortcut paths.'}
            }
            foreach($entry in $previous.Shortcuts){if(-not(Test-Path -LiteralPath $entry.Path) -or (Get-KitHash $entry.Path) -ne $entry.InstalledHash){throw 'An existing kit shortcut changed; preserve it for review.'}}
            $previousPath=Join-Path $instanceRoot 'previous-installation.json'
            Copy-Item -LiteralPath $receiptPath -Destination $previousPath
        }else{$previous=$null}
    }
    $package=Join-Path $instanceRoot 'package'
    New-Item -ItemType Directory -Path $package|Out-Null
    foreach($name in @('kit.json','components.json','runtimes.json','Install.cmd','bootstrap.ps1','install.ps1','restore.ps1','update.ps1','uninstall.ps1','Test-Kit.ps1','build.ps1','README.md','AGENTS.md','LICENSE','THIRD_PARTY.md','SKILL.md','src','scripts','docs')){
        $source=Join-Path $PSScriptRoot $name
        if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $package $name) -Recurse}
    }
    $package=Get-KitPhysicalPath $package
    $build=& (Join-Path $package 'build.ps1') -OutputDirectory (Join-Path $instanceRoot 'bin')
    $launcher=Get-KitPhysicalPath $build.Launcher
    $bridgePackage=$null;$bridgeReceipt=$null;$orbPackage=$null;$orbDestination=$null
    if($WithBridge){
        $bridgePackage=Get-KitComponent $manifest.bridge $Destination $ProxyUri
        $NodePath=Resolve-KitExecutable $NodePath 'node.exe'
        $bridgeDestination=Join-Path $instanceRoot 'bridge'
        $hostName=[IO.Path]::GetFileNameWithoutExtension($codex.Executable)
        & (Join-Path $bridgePackage 'scripts/Install-Bridge.ps1') -ComponentOnly -Destination $bridgeDestination -ProxyUri $ProxyUri -CodexHome $CodexHome -NodePath $NodePath -PythonPath $PythonPath -HostProcessName @($hostName)
        $bridgeReceipt=Join-Path $bridgeDestination 'installation.json'
    }
    if($WithQuotaOrb){
        $orbPackage=Get-KitComponent $manifest.quotaOrb $Destination $ProxyUri
        $orbDestination=Join-Path $instanceRoot 'quota-orb'
        & (Join-Path $orbPackage 'install.ps1') -Destination $orbDestination -NoShortcuts
    }
    $envState=Join-Path $instanceRoot 'env-transaction.json'
    $envScript=Join-Path $package 'scripts/env-edit.py'
    $envArgs=@('prepare','--state',$envState,'--config',(Join-Path $CodexHome '.env'),'--proxy',$ProxyUri,'--no-proxy',[string]$NoProxy,'--instance',$instance)
    if($previous){$envArgs+=@('--previous-state',$previous.EnvState)}
    & $PythonPath -X utf8 $envScript @envArgs
    if($LASTEXITCODE -ne 0){throw 'Proxy configuration preparation failed.'}
    $envRecord=Get-Content -LiteralPath $envState -Raw|ConvertFrom-Json
    if($envRecord.values.NO_PROXY.Split(',') -contains '*'){throw 'NO_PROXY=* would bypass the selected proxy. Review the existing setting first.'}
    $bypass=($envRecord.values.NO_PROXY.Split(',')|ForEach-Object {if($_ -eq '::1'){'[::1]'}else{$_}}) -join ';'
    if($bypass -notmatch '(^|;)<local>(;|$)'){$bypass+=';<local>'}
    $launchConfig=Join-Path $instanceRoot 'launch.json'
    $launchSettings=[ordered]@{Version=$metadata.version;Aumid=$codex.Aumid;ProxyUri=$ProxyUri;NoProxy=$envRecord.values.NO_PROXY;ProxyBypassList=$bypass;CodexHome=$CodexHome;LogPath=(Join-Path $Destination 'launcher.log');QuotaOrbPath=$null;Bridge=$null}
    if($WithQuotaOrb){$launchSettings.QuotaOrbPath=Join-Path $orbDestination 'QuotaOrb.exe'}
    if($WithBridge){$launchSettings.Bridge=@{ReceiptPath=$bridgeReceipt;RestoreScript=(Join-Path $bridgePackage 'scripts/Restore-Bridge.ps1');PowerShellPath=$powerShellPath}}
    Write-KitJson $launchConfig $launchSettings
    if(-not $NoShortcuts -and $ShortcutPath.Count -eq 0){
        if($previous){$ShortcutPath=@($previous.Shortcuts|Where-Object {-not $_.PSObject.Properties['Kind'] -or $_.Kind -eq 'codex'}|ForEach-Object Path)}
        else{$ShortcutPath=@((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex (Proxy).lnk'),(Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex (Proxy).lnk'))}
    }
    $entries=@();$shell=New-Object -ComObject WScript.Shell;$index=0
    $requests=@($ShortcutPath|ForEach-Object {[pscustomobject]@{Path=$_;Kind='codex'}})
    if($WithQuotaOrb -and -not $NoShortcuts -and -not $NoQuotaShortcut){
        $folders=@($ShortcutPath|ForEach-Object {Split-Path -Parent ([IO.Path]::GetFullPath($_))}|Sort-Object -Unique)
        foreach($folder in $folders){$requests+=[pscustomobject]@{Path=(Join-Path $folder 'Quota Orb.lnk');Kind='quota'}}
    }
    foreach($request in $requests){
        $path=$request.Path
        if([IO.Path]::GetExtension($path) -ine '.lnk'){throw 'ShortcutPath must name a .lnk file.'}
        $actual=Get-KitPhysicalPath $path
        if(@($entries|Where-Object Path -eq $actual).Count){throw 'Duplicate shortcut target.'}
        New-Item -ItemType Directory -Path (Split-Path -Parent $actual) -Force|Out-Null
        $old=Get-KitShortcut $actual;$backup=$null;$beforeHash=$null
        if($old){$backup=Join-Path $instanceRoot ("shortcut-before-$index.lnk");Copy-Item -LiteralPath $actual -Destination $backup;$beforeHash=$old.Hash}
        $stage=Join-Path $instanceRoot ("shortcut-after-$index.lnk");$link=$shell.CreateShortcut($stage)
        $link.TargetPath=$launcher;$link.Arguments='--config "'+$launchConfig+'"';$link.WorkingDirectory=Split-Path -Parent $launcher
        $link.IconLocation=if($old -and $old.Icon){$old.Icon}else{$codex.Executable+',0'}
        $link.Description='Codex 专用代理启动；附加组件由 Desktop Kit 管理'
        if($request.Kind -eq 'quota'){$link.Arguments+=' --toggle-orb';$link.Description='Quota Orb 手动开关';$link.IconLocation=$launchSettings.QuotaOrbPath+',0'}
        $link.Save()
        $entries+=[pscustomobject]@{Path=$actual;Kind=$request.Kind;Backup=$backup;BeforeHash=$beforeHash;Staged=$stage;InstalledHash=(Get-KitHash $stage)};$index++
    }
    $receipt=[pscustomobject]@{
        SchemaVersion=1;Product='codex-desktop-kit';Status='prepared';Version=$metadata.version;InstanceId=$instance;Destination=$Destination;PackageRoot=$package;
        PreparedAt=[DateTimeOffset]::Now.ToString('o');CodexHome=$CodexHome;ProxyUri=$ProxyUri;PythonPath=$PythonPath;NodePath=$NodePath;
        EnvState=$envState;LaunchConfig=$launchConfig;Launcher=$launcher;LauncherHash=(Get-KitHash $launcher);Shortcuts=$entries;NoQuotaShortcut=[bool]$NoQuotaShortcut;
        BridgePackage=$bridgePackage;BridgeReceipt=$bridgeReceipt;QuotaPackage=$orbPackage;QuotaDestination=$orbDestination;
        ComponentVersions=@{bridge=$(if($WithBridge){$manifest.bridge.version}else{$null});quotaOrb=$(if($WithQuotaOrb){$manifest.quotaOrb.version}else{$null})};
        PreviousReceipt=$previousPath;ColdRestartVerified=$false;SystemProxyTunOffVerified=$false
    }
    Write-KitJson $receiptPath $receipt
    & $PythonPath -X utf8 $envScript apply --state $envState
    if($LASTEXITCODE -ne 0){throw 'Proxy configuration commit failed.'}
    if($WithBridge){& (Join-Path $bridgePackage 'scripts/Enable-Bridge.ps1') -InstallationPath $bridgeReceipt}
    foreach($entry in $entries){Set-KitFile $entry.Path $entry.Staged $entry.BeforeHash}
    $receipt.Status='enabled';Write-KitJson $receiptPath $receipt
    & (Join-Path $package 'Test-Kit.ps1') -InstallationPath $receiptPath
    if($Launch){if($entries.Count){Start-KitDesktop $entries[0].Path}else{Start-KitDesktop $launcher ('--config "'+$launchConfig+'"')}}
    Write-Output "Installed Codex Desktop Kit $($metadata.version). Finish work, fully exit Codex, then open the selected shortcut for live acceptance."
}catch{
    if($receipt){
        try{& (Join-Path $receipt.PackageRoot 'restore.ps1') -InstallationPath $receiptPath -Confirm:$false}catch{Write-Warning 'Automatic restore needs review; installation receipt and backups were preserved.'}
    }
    throw
}finally{$mutex.ReleaseMutex();$mutex.Dispose()}
