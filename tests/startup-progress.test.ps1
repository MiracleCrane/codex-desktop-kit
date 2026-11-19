# No real application, gateway, or foreground window is opened.
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $PSScriptRoot '..\scripts'
$wrapper = Join-Path $scripts 'Start-CodexWithProgress.ps1'
$viewer = Join-Path $scripts 'Show-CodexLaunchProgress.ps1'
foreach ($path in @($wrapper, $viewer)) {
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw ($errors | Out-String) }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('kit-ui-fixture-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
$statusPath = Join-Path (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Temp') ('codex-launch-' + [guid]::NewGuid().ToString('N') + '.status')
try {
    Copy-Item -LiteralPath $wrapper -Destination $root
    $fixture = Join-Path $root 'Start-CodexWithProgress.ps1'
    # Omit viewer to exercise the quiet fallback.
    @'
param($ConfigPath, $Mode, [switch]$PrepareOnly)
if ($ConfigPath -eq 'fail') { throw 'fixture launcher failed' }
[pscustomobject]@{
    Status = if ($PrepareOnly) { 'prepared-not-launched' } else { 'package-launch-requested' }
    Mode = $Mode
}
'@ | Set-Content -LiteralPath (Join-Path $root 'Launch-Compatibility.ps1') -Encoding UTF8
    $value = & $fixture -ConfigPath 'ok' -Mode Original
    if ($value.Status -ne 'package-launch-requested' -or $value.Mode -ne 'Original') { throw 'Wrapper changed launcher result.' }
    $value = & $fixture -ConfigPath 'ok' -PrepareOnly
    if ($value.Status -ne 'prepared-not-launched') { throw 'Wrapper did not pass through PrepareOnly.' }
    $didFail = $false
    try { & $fixture -ConfigPath 'fail' | Out-Null }
    catch { if ($_.Exception.Message -ne 'fixture launcher failed') { throw }; $didFail = $true }
    if (!$didFail) { throw 'Wrapper swallowed launcher failure.' }

    # The real viewer creates and lays out the WPF card, but never calls ShowDialog.
    [IO.File]::WriteAllText($statusPath, 'launching')
    $shell = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh.exe' })
    $render = & $shell -NoProfile -NonInteractive -STA -File $viewer -StatusPath $statusPath -RenderOnly
    if ($LASTEXITCODE -ne 0 -or ($render -join ' ') -notmatch 'Starting Codex') { throw 'Offscreen viewer layout failed.' }
    if (Test-Path -LiteralPath $statusPath) { throw 'Viewer did not clean up its status file.' }
} finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $statusPath -ErrorAction SilentlyContinue
}
'PASS: optional viewer, quiet fallback, launch result/error fidelity and offscreen WPF layout.'
