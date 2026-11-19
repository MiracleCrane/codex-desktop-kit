# Optional interactive launcher. The existing command remains the quiet default.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('Compatibility','Original')][string]$Mode='Compatibility',
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Launch-Compatibility.ps1'
if ($PrepareOnly) {
    & $launcher -ConfigPath $ConfigPath -Mode $Mode -PrepareOnly
    return
}

# Pass only a randomly named status file. No config, paths to Codex, or errors go in it.
$statusPath = $null
$helper = $null
try {
    $shell = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' })
    $viewer = Join-Path $PSScriptRoot 'Show-CodexLaunchProgress.ps1'
    if ((Test-Path -LiteralPath $shell -PathType Leaf) -and (Test-Path -LiteralPath $viewer -PathType Leaf)) {
        # Packaged hosts can remap TEMP differently in the child process.
        $statusPath = Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Temp') ("codex-launch-" + [guid]::NewGuid().ToString('N') + '.status')
        [IO.File]::WriteAllText($statusPath, 'launching')
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $shell
        $info.Arguments = '-NoProfile -NonInteractive -STA -WindowStyle Hidden -File "' + $viewer + '" -StatusPath "' + $statusPath + '"'
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $helper = [Diagnostics.Process]::Start($info)
        if ($null -eq $helper) { throw 'Progress viewer process was not created.' }
    }
} catch {
    if ($statusPath) { Remove-Item -LiteralPath $statusPath -ErrorAction SilentlyContinue }
    $statusPath = $null
    Write-Verbose 'Progress window unavailable. Starting Codex without it.'
}

function Publish-Status([string]$State) {
    if (!$statusPath) { return }
    try {
        # The reader tolerates a short sharing race. Do not recreate a file
        # already removed by a closed or timed-out viewer.
        $stream = [IO.File]::Open($statusPath, 'Open', 'Write', 'Read')
        try {
            $payload = [Text.Encoding]::ASCII.GetBytes($State)
            $stream.Write($payload, 0, $payload.Length)
            $stream.SetLength($payload.Length)
        } finally { $stream.Dispose() }
    } catch { Write-Verbose 'Progress status could not be written.' }
}

try {
    $result = & $launcher -ConfigPath $ConfigPath -Mode $Mode
    if ($result.Status -contains 'package-launch-requested') { Publish-Status 'dispatched' }
    else { Publish-Status 'unconfirmed' }
    $result
} catch {
    Publish-Status 'failed'
    throw
} finally {
    if ($helper) {
        try {
            if ($helper.HasExited -and $statusPath) { Remove-Item -LiteralPath $statusPath -ErrorAction SilentlyContinue }
        } catch { Write-Verbose 'Progress viewer cleanup was unavailable.' }
        finally { $helper.Dispose() }
    }
}
