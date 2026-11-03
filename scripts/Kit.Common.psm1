Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-KitHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Enter-KitLock([string]$CodexHome) {
    $name='Local\CodexDesktopKit-'+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($CodexHome.ToLowerInvariant()))).Substring(0,24)
    $lock=[Threading.Mutex]::new($false,$name)
    if(-not $lock.WaitOne(0)){$lock.Dispose();throw 'Another installer is managing this Codex home.'}
    $lock
}
function Write-KitJson([string]$Path,$Value) {
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}
    else{[IO.File]::Move($temp,$Path)}
}
function Get-KitPhysicalPath([string]$Path) {
    if(-not ('KitPhysicalPath' -as [type])){
        Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class KitPhysicalPath {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint mode,uint flags,IntPtr template);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle h,StringBuilder s,uint n,uint flags);
 public static string Resolve(string path){using(var h=CreateFile(path,0,7,IntPtr.Zero,3,0x02000000,IntPtr.Zero)){
  if(h.IsInvalid)throw new IOException("Cannot resolve physical path");var s=new StringBuilder(32768);uint n=GetFinalPathNameByHandle(h,s,(uint)s.Capacity,0);
  if(n==0||n>=s.Capacity)throw new IOException("Cannot resolve physical path");string value=s.ToString();
  return value.StartsWith(@"\\?\UNC\")?@"\\"+value.Substring(8):value.StartsWith(@"\\?\")?value.Substring(4):value;}}
}
'@
    }
    $probe=[IO.Path]::GetFullPath($Path);$suffix=@()
    while(-not(Test-Path -LiteralPath $probe)){$suffix=@((Split-Path -Leaf $probe))+$suffix;$parent=Split-Path -Parent $probe;if(-not $parent){throw 'Invalid path'};$probe=$parent}
    $actual=[KitPhysicalPath]::Resolve($probe)
    foreach($part in $suffix){$actual=Join-Path $actual $part}
    $actual
}
function Assert-KitDestination([string]$Destination,[string]$CodexHome) {
    $path=Get-KitPhysicalPath $Destination
    if($path -eq [IO.Path]::GetPathRoot($path)){throw 'Choose a dedicated installation directory.'}
    $blocked=@($CodexHome,(Join-Path $HOME '.agents'),(Join-Path $HOME '.claude'),$env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)
    foreach($root in $blocked){if($root){$resolved=(Get-KitPhysicalPath $root).TrimEnd('\');if($path -eq $resolved -or $path.StartsWith($resolved+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Install outside configuration, Skill and synchronized directories.'}}}
    $parent=$path
    while($parent){if(Test-Path -LiteralPath (Join-Path $parent '.git')){throw 'Install outside source repositories.'};$next=Split-Path -Parent $parent;if($next -eq $parent){break};$parent=$next}
    $path
}
function Get-KitChildPath([string]$Root,[string]$Path) {
    $base=(Get-KitPhysicalPath $Root).TrimEnd('\')
    $actual=Get-KitPhysicalPath $Path
    if(-not $actual.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'A managed child path resolves outside the installation directory.'}
    $actual
}
function Resolve-KitExecutable([string]$Value,[string]$Name) {
    if(-not $Value){$command=Get-Command $Name -ErrorAction Stop|Select-Object -First 1;$Value=$command.Source}
    if($Value -match '\\Microsoft\\WindowsApps\\'){throw "Use an installed runtime executable, not the $Name app alias."}
    Get-KitPhysicalPath $Value
}
function Assert-KitProxy([string]$ProxyUri) {
    $u=[uri]$ProxyUri
    if($u.Scheme -ne 'http' -or -not $u.IsLoopback -or $u.UserInfo -or $u.Query -or $u.Fragment -or $u.AbsolutePath -ne '/' -or $u.Port -lt 1){throw 'Use a local HTTP/mixed proxy URI without credentials.'}
    $client=[Net.Sockets.TcpClient]::new()
    try{if(-not $client.ConnectAsync($u.DnsSafeHost,$u.Port).Wait(2500) -or -not $client.Connected){throw 'Local proxy is not listening.'}}finally{$client.Dispose()}
}
function Get-KitCodex {
    $package=Get-AppxPackage -Name OpenAI.Codex|Sort-Object Version -Descending|Select-Object -First 1
    if(-not $package){throw 'Install and sign in to the official Codex Windows desktop app first.'}
    $manifest=Get-AppxPackageManifest -Package $package
    $application=@($manifest.Package.Applications.Application)[0]
    [pscustomobject]@{Aumid=($package.PackageFamilyName+'!'+$application.Id);Executable=(Join-Path $package.InstallLocation $application.Executable);Version=[string]$package.Version;PackageRoot=$package.InstallLocation}
}
function Get-KitComponent($Component,[string]$Destination,[string]$ProxyUri) {
    if($Component.sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Component SHA256 pin is missing.'}
    $uri=[uri]$Component.url
    if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.UserInfo){throw 'Component releases must use the pinned GitHub HTTPS URL.'}
    $download=Get-KitChildPath $Destination (Join-Path $Destination ('downloads/'+$Component.id+'-'+$Component.version+'.zip'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $download) -Force|Out-Null
    if(-not(Test-Path -LiteralPath $download) -or (Get-KitHash $download) -ne $Component.sha256){
        $partial=Get-KitChildPath $Destination ($download+'.partial')
        Invoke-WebRequest -Uri $Component.url -Proxy $ProxyUri -OutFile $partial -TimeoutSec 120
        if((Get-KitHash $partial) -ne $Component.sha256){throw 'Downloaded component failed SHA256 verification.'}
        Move-Item -LiteralPath $partial -Destination $download -Force
    }
    $package=Get-KitChildPath $Destination (Join-Path $Destination ('packages/'+$Component.id+'/'+$Component.version+'/'+[guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $package -Force|Out-Null
    $archive=[IO.Compression.ZipFile]::OpenRead($download)
    try{
        foreach($entry in $archive.Entries){
            $target=[IO.Path]::GetFullPath((Join-Path $package $entry.FullName))
            if(-not $target.StartsWith($package.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $entry.FullName.Contains(':')){throw 'Unsafe release archive path.'}
            if((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000){throw 'Symlink entries are not accepted.'}
            if($entry.Name){New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force|Out-Null;[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)}
        }
    }finally{$archive.Dispose()}
    Get-KitPhysicalPath $package
}
function Get-KitShortcut([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    $actual=Get-KitPhysicalPath $Path;$link=(New-Object -ComObject WScript.Shell).CreateShortcut($actual)
    [pscustomobject]@{Path=$actual;Target=$link.TargetPath;Arguments=$link.Arguments;Icon=$link.IconLocation;WorkingDirectory=$link.WorkingDirectory;Hash=(Get-KitHash $actual)}
}
function Set-KitFile([string]$Path,[string]$Source,[string]$ExpectedHash) {
    $bytes=[IO.File]::ReadAllBytes($Source)
    $mode=if($ExpectedHash){[IO.FileMode]::Open}else{[IO.FileMode]::CreateNew}
    $stream=[IO.FileStream]::new($Path,$mode,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
    try{
        $copy=[IO.MemoryStream]::new();try{$stream.CopyTo($copy);$before=$copy.ToArray()}finally{$copy.Dispose()}
        if($ExpectedHash){$sha=[Security.Cryptography.SHA256]::HashData($before);if([Convert]::ToHexString($sha).ToLowerInvariant() -ne $ExpectedHash){throw 'Shortcut changed during installation.'}}
        try{$stream.Position=0;$stream.Write($bytes,0,$bytes.Length);$stream.SetLength($bytes.Length);$stream.Flush($true)}
        catch{$stream.Position=0;$stream.Write($before,0,$before.Length);$stream.SetLength($before.Length);$stream.Flush($true);throw}
    }finally{$stream.Dispose()}
}
function Start-KitDesktop([string]$Path,[string]$Arguments='') {
    $shell=New-Object -ComObject Shell.Application;$handle=0
    $view=$shell.Windows().FindWindowSW(0,0,8,[ref]$handle,1)
    if(-not $view){throw 'A normal Explorer desktop is needed for persistent GUI startup.'}
    $view.Document.Application.ShellExecute($Path,$Arguments,(Split-Path -Parent $Path),'open',0)
}
Export-ModuleMember -Function *-Kit*
