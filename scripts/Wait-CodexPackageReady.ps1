# Dot-source only. Read-only deployment gate; no app/service/process changes.
Set-StrictMode -Version Latest
function Get-CodexDeploymentSnapshot {
    [Windows.Management.Deployment.PackageManager,Windows.Management.Deployment,ContentType=WindowsRuntime] | Out-Null
    $manager = New-Object Windows.Management.Deployment.PackageManager
    $packages = @($manager.FindPackagesForUser('') | Where-Object { $_.Id.Name -eq 'OpenAI.Codex' } |
        Sort-Object { [version]('{0}.{1}.{2}.{3}' -f $_.Id.Version.Major,$_.Id.Version.Minor,$_.Id.Version.Build,$_.Id.Version.Revision) } -Descending)
    if (!$packages.Count) { return [pscustomobject]@{PackageFullName=$null;Ready=$false;Reason='not-registered'} }
    $package = $packages[0]
    $status = $package.Status
    $deployment = [bool]$status.DeploymentInProgress
    $servicing = [bool]$status.Servicing
    $ok = [bool]$status.VerifyIsOK()
    $partial = [bool]$status.IsPartiallyStaged
    [pscustomobject]@{PackageFullName=[string]$package.Id.FullName;Ready=(!$deployment -and !$servicing -and !$partial -and $ok);Reason=if($deployment){'deployment-in-progress'}elseif($servicing){'servicing'}elseif($partial){'partially-staged'}elseif(!$ok){'not-healthy'}else{'ready'}}
}
function Assert-CodexPackageReady {
    param([Parameter(Mandatory)][string]$ExpectedPackageFullName,
          [scriptblock]$ReadStatus={ Get-CodexDeploymentSnapshot })
    try { $snapshot = & $ReadStatus } catch { throw 'Unable to read current package deployment status; no application was started.' }
    if (!$snapshot -or !$snapshot.Ready -or $snapshot.PackageFullName -cne $ExpectedPackageFullName) {
        throw 'Package changed or is not ready; no application was started. Wait for the update and retry.'
    }
    $snapshot
}
function Wait-CodexPackageReady {
    param([ValidateRange(1,180)][int]$TimeoutSeconds=180,
          [ValidateRange(1,10000)][int]$PollMilliseconds=1000,
          [ValidateRange(2,10)][int]$StableSamples=3,
          [scriptblock]$ReadStatus={ Get-CodexDeploymentSnapshot })
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $last=$null; $stable=0
    do {
        try { $snapshot = & $ReadStatus } catch { throw 'Unable to read current package deployment status; no application was started.' }
        if (!$snapshot) { throw 'Unknown package deployment status; no application was started.' }
        if ($snapshot.Ready -and $snapshot.PackageFullName) {
            if ($snapshot.PackageFullName -ceq $last) { $stable++ } else { $last=$snapshot.PackageFullName; $stable=1 }
            if ($stable -ge $StableSamples) { return $snapshot }
        } else { $last=$null; $stable=0 }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw 'Package update/readiness wait timed out; no application was started. Retry after installation completes.'
}
