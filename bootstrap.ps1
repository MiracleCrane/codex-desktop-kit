#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Destination=(Join-Path $env:LOCALAPPDATA 'Programs\CodexDesktopKit'),
    [string]$ProxyUri,
    [switch]$WithBridge,
    [string]$MagpiePath,
    [string]$MagpieBaseUrl,
    [switch]$WithQuotaOrb,
    [switch]$UseBundledRuntimes,
    [switch]$PrepareOnly,
    [switch]$NoShortcuts,
    [string]$CodexHome
)
$ErrorActionPreference='Stop'
if($WithBridge -and $MagpiePath){throw 'Select Magpie or the transport bridge, not both.'}
if(-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'The bootstrap currently supports Windows x64. Use explicit compatible runtimes on other architectures.'}
if(-not $ProxyUri){
    $answer=Read-Host 'Local HTTP/mixed proxy port or URI [7897]'
    if(-not $answer){$answer='7897'}
    $ProxyUri=if($answer -match '^\d+$'){"http://127.0.0.1:$answer"}else{$answer}
    $WithQuotaOrb=(Read-Host 'Install optional Quota Orb? y/N') -match '^(y|yes)$'
    if(-not $MagpiePath){$WithBridge=(Read-Host 'Install optional transport bridge? y/N') -match '^(y|yes)$'}
}
$proxy=[uri]$ProxyUri
if($proxy.Scheme -ne 'http' -or -not $proxy.IsLoopback -or $proxy.UserInfo -or $proxy.Query -or $proxy.Fragment -or $proxy.AbsolutePath -ne '/'){throw 'Use a local HTTP/mixed proxy without embedded credentials.'}
$Destination=[IO.Path]::GetFullPath($Destination)
Import-Module (Join-Path $PSScriptRoot 'scripts/Kit.Common.psm1') -Force
$effectiveHome=if($CodexHome){$CodexHome}elseif($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $HOME '.codex'}
$Destination=Assert-KitDestination $Destination $effectiveHome
if($Destination -eq [IO.Path]::GetPathRoot($Destination)){throw 'Choose a dedicated installation directory.'}
if($Destination.StartsWith($PSScriptRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $Destination -eq $PSScriptRoot){throw 'Install outside the extracted source package.'}
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtimes.json') -Raw|ConvertFrom-Json
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-LocalRuntime($entry){
    $root=Get-KitChildPath $Destination (Join-Path $Destination ('runtimes\'+$entry.name.Replace('.','').Replace(' ','')+'-'+$entry.version))
    $exe=Join-Path $root $entry.executable
    $receipt=Join-Path $root 'runtime-receipt.json'
    if(Test-Path -LiteralPath $receipt){
        $saved=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
        if($saved.archiveSha256 -ne $entry.sha256 -or -not(Test-Path -LiteralPath $exe) -or (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -ne $saved.executableSha256){throw 'A locally provisioned runtime changed; inspect it before replacing it.'}
        return $exe
    }
    $downloads=Get-KitChildPath $Destination (Join-Path $Destination 'downloads')
    New-Item -ItemType Directory -Path $downloads -Force|Out-Null
    $archive=Get-KitChildPath $Destination (Join-Path $downloads ($entry.name.Replace('.','').Replace(' ','')+'-'+$entry.version+'.zip'))
    if(-not(Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -ne $entry.sha256){
        $partial=Get-KitChildPath $Destination ($archive+'.partial')
        Write-Host ('Downloading '+$entry.name+' '+$entry.version+' into the kit directory...')
        $complete=$false
        $curl=Join-Path $env:SystemRoot 'System32\curl.exe'
        if(-not(Test-Path -LiteralPath $curl)){throw 'Windows curl.exe is unavailable. Use the advanced installer with existing runtimes.'}
        for($attempt=1;$attempt -le 3;$attempt++){
            & $curl --fail --silent --show-error --location --proto-redir '=https' --max-redirs 5 --connect-timeout 15 --max-time 180 --proxy $ProxyUri --noproxy 'localhost,127.0.0.1' --continue-at - --output $partial $entry.url
            $downloadExit=$LASTEXITCODE
            if($downloadExit -eq 0){$complete=$true;break}
            if($downloadExit -notin @(18,28,52,56) -or $attempt -eq 3){throw 'Runtime download failed. Check the proxy/TLS path; partial data was preserved.'}
            Write-Host ('Transfer interrupted; resuming attempt '+($attempt+1)+' of 3...')
            Start-Sleep -Seconds 1
        }
        if(-not $complete -or (Get-FileHash -LiteralPath $partial).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'Runtime archive SHA256 mismatch; it will not be executed.'}
        Move-Item -LiteralPath $partial -Destination $archive -Force
    }
    if(Test-Path -LiteralPath $root){throw 'A partial runtime directory already exists. Preserve it for inspection before retrying.'}
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try{
        foreach($file in $zip.Entries){
            $target=[IO.Path]::GetFullPath((Join-Path $root $file.FullName))
            if(-not $target.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $file.FullName.Contains(':')){throw 'Unsafe runtime archive entry.'}
            if((($file.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'Runtime archive symlinks are not supported.'}
            if($file.Name){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null;[IO.Compression.ZipFileExtensions]::ExtractToFile($file,$target,$false)}
        }
    }finally{$zip.Dispose()}
    if(-not(Test-Path -LiteralPath $exe)){throw 'Runtime archive did not contain the pinned executable.'}
    [IO.File]::WriteAllText($receipt,(@{archiveSha256=$entry.sha256;executableSha256=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant();source=$entry.url}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $exe
}

function Find-CompatibleRuntime([string]$name){
    if($UseBundledRuntimes){return $null}
    $command=Get-Command $name -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not $command -or $command.Source -match '\\Microsoft\\WindowsApps\\'){return $null}
    $path=$command.Source
    if($name -eq 'pwsh.exe'){
        & $path -NoProfile -Command 'if ($PSVersionTable.PSVersion -lt [version]"7.2") { exit 1 }'|Out-Null
    }elseif($name -eq 'python.exe'){
        & $path -I -c 'import sys,tomllib;sys.exit(0 if sys.version_info >= (3,11) else 1)' 2>$null
    }else{
        $version=& $path --version
        if([int]($version -replace '^v(\d+).*','$1') -lt 22 -or -not(Test-Path -LiteralPath (Join-Path (Split-Path -Parent $path) 'npm.cmd'))){return $null}
    }
    if($LASTEXITCODE -ne 0){return $null}
    $path
}
$pwsh=Find-CompatibleRuntime 'pwsh.exe';if(-not $pwsh){$pwsh=Get-LocalRuntime $manifest.powershell}
$python=Find-CompatibleRuntime 'python.exe';if(-not $python){$python=Get-LocalRuntime $manifest.python}
$node=$null
if($WithBridge){$node=Find-CompatibleRuntime 'node.exe';if(-not $node){$node=Get-LocalRuntime $manifest.node}}
if($PrepareOnly){[pscustomobject]@{PowerShellPath=$pwsh;PythonPath=$python;NodePath=$node}|ConvertTo-Json;return}
$arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'install.ps1'),'-Destination',$Destination,'-ProxyUri',$ProxyUri,'-PythonPath',$python)
if($WithQuotaOrb){$arguments+='-WithQuotaOrb'}
if($WithBridge){$arguments+=@('-WithBridge','-NodePath',$node)}
if($MagpiePath){$arguments+=@('-MagpiePath',$MagpiePath)}
if($MagpieBaseUrl){$arguments+=@('-MagpieBaseUrl',$MagpieBaseUrl)}
if($NoShortcuts){$arguments+='-NoShortcuts'}
if($CodexHome){$arguments+=@('-CodexHome',$CodexHome)}
& $pwsh @arguments
if($LASTEXITCODE -ne 0){throw 'Kit installation did not complete; read its recovery message.'}
