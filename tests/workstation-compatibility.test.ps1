# Isolated fixture: no real package, signature, process, network, or application launch.
$ErrorActionPreference='Stop'
$scriptPath = Join-Path $PSScriptRoot '..\scripts\Launch-Compatibility.ps1'
$tokens=$null; $errors=$null
[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw ($errors | Out-String) }
$root=Join-Path ([IO.Path]::GetTempPath()) ('kit-compat-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$resources=Join-Path $root 'package\app\resources'
[IO.Directory]::CreateDirectory($resources) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $root 'home')) | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'package\app\ChatGPT.exe'),'fixture desktop')
[IO.File]::WriteAllText((Join-Path $resources 'codex.exe'),'fixture backend')
[IO.File]::WriteAllText((Join-Path $resources 'helper.exe'),'fixture helper')
$global:fixtureVersion='1.0.0.0'
$global:fixtureSignature='Valid'
$global:fixtureActive=$false
function Get-AppxPackage { param($Name) [pscustomobject]@{Version=$global:fixtureVersion;InstallLocation=(Join-Path $root 'package');PackageFullName="fixture-$global:fixtureVersion"} }
function Get-AuthenticodeSignature { param($LiteralPath) [pscustomobject]@{Status=$global:fixtureSignature;SignerCertificate=[pscustomobject]@{Subject='CN=OpenAI OpCo LLC, O=OpenAI OpCo LLC'}} }
function Get-Process { param($Name,$ErrorAction) if($global:fixtureActive){[pscustomobject]@{Id=1}} }
$config=Join-Path $root 'profile.json'
$c=@{Enabled=$true;ComputerName=$env:COMPUTERNAME;CodexHome=(Join-Path $root 'home');CacheRoot=(Join-Path $root 'cache');ProxyUri='http://127.0.0.1:7897';NoProxy='localhost';ProxyBypassList='localhost';AuxiliaryFiles=@('helper.exe')}
function Save-Profile { $c | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding UTF8 }
function Expect-Failure([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { if($_.Exception.Message -match $Pattern){return}; throw }
    throw "Expected failure: $Pattern"
}
Save-Profile
$a=& $scriptPath -ConfigPath $config -PrepareOnly
if($a.Status -ne 'prepared-not-launched'){throw 'Preparation result missing'}
$original=& $scriptPath -ConfigPath $config -PrepareOnly
if($original.BackendPath -ne $a.BackendPath){throw 'Cache not reused'}
$global:fixtureVersion='2.0.0.0'
[IO.File]::WriteAllText((Join-Path $resources 'codex.exe'),'fixture backend v2')
$b=& $scriptPath -ConfigPath $config -PrepareOnly
if($b.BackendPath -eq $a.BackendPath -or !(Test-Path -LiteralPath $a.BackendPath)){throw 'Version isolation failed'}
$previous=Join-Path $c.CacheRoot 'current.json.previous'
$previousHash=(Get-FileHash -LiteralPath $previous).Hash
& $scriptPath -ConfigPath $config -PrepareOnly | Out-Null
if((Get-FileHash -LiteralPath $previous).Hash -ne $previousHash){throw 'Previous manifest overwritten'}
$c.Enabled=$false;Save-Profile
Expect-Failure { & $scriptPath -ConfigPath $config -PrepareOnly } 'disabled'
$c.Enabled=$true;$c.ComputerName='another-machine';Save-Profile
Expect-Failure { & $scriptPath -ConfigPath $config -PrepareOnly } 'different computer'
$c.ComputerName=$env:COMPUTERNAME;Save-Profile
$global:fixtureSignature='HashMismatch'
Expect-Failure { & $scriptPath -ConfigPath $config -PrepareOnly } 'signature'
$global:fixtureSignature='Valid'
$c.AuxiliaryFiles=@('missing.exe');Save-Profile
Expect-Failure { & $scriptPath -ConfigPath $config -PrepareOnly } 'missing'
$c.AuxiliaryFiles=@('helper.exe');Save-Profile
$global:fixtureActive=$true
Expect-Failure { & $scriptPath -ConfigPath $config } 'already running'
$global:fixtureActive=$false
[IO.File]::WriteAllText($b.BackendPath,'tampered fixture')
Expect-Failure { & $scriptPath -ConfigPath $config -PrepareOnly } 'integrity mismatch'
"PASS: parse, prepare, cache reuse, version isolation, previous manifest, opt-in, machine scope, signature rejection, missing helper, active-process guard, tamper rejection. Fixture retained at $root"
