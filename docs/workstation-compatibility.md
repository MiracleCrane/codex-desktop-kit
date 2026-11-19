# Workstation-specific compatibility profile (experimental)

This branch adds an **explicit opt-in profile for one selected workstation**. It is not a default installation mode, not a general Codex repair, and not a claim about security-product identification rules. Other computers keep their ordinary launcher unless separately investigated and authorized.

The installed desktop stays unmodified. A byte-identical, signature-checked copy of its bundled backend is launched under a compatibility basename through CODEX_CLI_PATH. This does not disable monitoring, change system security, edit WindowsApps, migrate history, install services, or change system proxy/TUN settings. Do not infer unchanged monitoring coverage merely from unchanged settings.

## When to return to Original mode

Keep the official bundled Codex backend as the day-to-day choice when normal use is responsive with it. Switch the daily shortcut to Original mode and retain the compatibility entry as an opt-in fallback. Original mode drops the backend override and skips compatibility-cache preparation while preserving the configured Codex home, proxy and bypasses. Keep any separately configured gateway behavior unchanged.

To verify the switch, close Codex normally and use the updated shortcut. Check that the new desktop actually uses the bundled backend, that existing history and a fresh conversation work, and that its proxy and configured gateway still work. A shortcut change or warm activation does not verify a cold start. If lag returns, record the installed version and what reproduced it before reconsidering the fallback. A responsive test on one computer does not establish a product-wide fix.

## Local deployment

Inspect the selected shortcut, original icon resource, kit receipt, optional Magpie/Orb choices, actual Codex home and proxy before deploying. Keep machine configuration and receipts/backups outside Git.

Create a local JSON profile containing:
- Enabled: true only after this workstation explicitly opts in.
- ComputerName: exact local computer name; another machine is rejected.
- CodexHome: absolute existing data directory; never create an empty replacement.
- CacheRoot: absolute writable dedicated runtime cache directory.
- ProxyUri: current local HTTP/mixed proxy URI without credentials.
- NoProxy and ProxyBypassList: preserve current local/intranet exclusions.
- AuxiliaryFiles: exact executable basenames required by the installed bundled backend, excluding codex.exe. Inventory from the official package; missing files stop preparation.

Run Windows PowerShell or PowerShell 7 with -NoProfile -File scripts/Launch-Compatibility.ps1 -ConfigPath "<local-profile>" -PrepareOnly.

PrepareOnly verifies/caches a version without closing or starting the application. Launch normally only after existing desktop/backend tasks have exited; omit PrepareOnly. Mode Original omits the backend override for the currently installed official desktop; it is not an application downgrade or database rollback.

Keep the daily shortcut and the explicit compatibility fallback clearly distinguishable. Back up its previous .lnk and preserve the original icon resource. Do not rewrite unrelated shortcuts or add login startup. Only one operator owns shortcut/receipt edits.

By default this entrypoint starts neither Magpie nor Orb. On the selected workstation only, an explicit local Gateway object may set Enabled=true, ExecutablePath to the already-installed approved Magpie executable, Port to its configured loopback gateway port, and TimeoutSeconds (1..120, default 20). Normal launch reuses the exact executable path or starts it with the fixed tray argument, then waits for a listening port owned by that executable. PrepareOnly never starts the gateway. gateway-status.json records readiness/failure without claiming successful model traffic. The launcher does not install, update, authenticate or reconfigure the gateway. Orb is not launched: preserve that separately only after its selected lifecycle is verified. This gateway addition is a review change until isolated and real startup acceptance pass.

## Package identity and child environment

The entrypoint activates a hidden Windows PowerShell worker with Invoke-CommandInDesktopPackage and PreventBreakaway. The worker verifies its native package identity matches the selected installed version before launching the desktop. Proxy and backend environment overrides are set inside that worker for the desktop child; no global environment is changed. Chromium receives explicit proxy arguments.

PreventBreakaway affects the launched process tree. Validate terminal/tools and remote execution as well as native package/updater APIs before calling the deployment accepted. It does not prove Store connectivity or that an update can install. Package activation only reports package-launch-requested; do not equate this with a working desktop or remote connection.

## Update behavior

Each launch inventories the currently registered official package rather than hard-coding a WindowsApps version. Valid OpenAI signatures are required for the desktop and backend. Compatibility mode and explicit PrepareOnly copy the backend plus configured helpers to a new version-and-content-addressed cache, verified against source SHA-256 values, and only then recorded in current.json. Previous manifest and prior caches remain. No running cached executable is overwritten; no old desktop is automatically paired with a new backend.

No network downloads or package updates are performed. Changed layout, missing helper, signature failure or cache mismatch stops launch and preserves data. Preparation is not compatibility acceptance: after every desktop update verify history loading, model reply, tools, remote executor registration and performance. Downgrading the installed package must be explicit and consider data compatibility.

## Validation status

Initial implementation is a review branch, not a released kit version. Before deployment, parse it on Windows, validate installed signature/layout and local profile with PrepareOnly, and run normal restart acceptance. Verify final process paths and proxy inheritance. A launch PID is not proof of remote connectivity. Keep sensitive logs, machine names, paths and binaries out of this repository.

## Launch while an update may be installing

The agreed workflow is manual cold launch: after using Codex's own update UI, if it automatically opens a window, the user closes it normally and then clicks the selected launcher; if no window opens, the user clicks the launcher directly. This entrypoint never closes an existing instance on the user's behalf. The experimental automatic dispatcher is not deployed or needed for this workflow.

Before ordinary launch, a Windows PowerShell 5 worker reads the registered package's WinRT status once. DeploymentInProgress, Servicing, partial staging, unhealthy, unreadable or unknown status immediately stops this launch attempt and tells the user to retry after installation. It does not poll, sleep or wait for the updater. A healthy already-installed new package proceeds with the bundled backend in Original mode or with matching-backend preparation in Compatibility mode. The exact full package name is passed to the package worker, which checks readiness and identity again; another fresh check is made just before process creation. PrepareOnly does not launch.

This is an immediate readiness guard, not an atomic deployment lock. A download or handoff may leave the old registered package reporting healthy, and Windows may start another deployment after the final check. Without a reliable intended-version signal the launcher cannot prove that a newer planned update has completed. A rejected launch does not cancel installation or start a fallback old package.

Microsoft documents these status properties in [PackageStatus](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.packagestatus). Readiness must be measured again rather than inferred from an existing WindowsApps directory.

The selected workstation deployment has passed both isolated suites and a read-only Windows PowerShell 5 check against its currently healthy registered package, with no application restart. This is not a test during real installation or a future-version update. The shared launch gate is deployed there; the separate local daily component coordinator is still not fully represented by the public Gateway-only implementation.
