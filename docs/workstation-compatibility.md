# Workstation-specific compatibility profile (experimental)

This branch adds an **explicit opt-in profile for one selected workstation**. It is not a default installation mode, not a general Codex repair, and not a claim about security-product identification rules. Other computers keep their ordinary launcher unless separately investigated and authorized.

The installed desktop stays unmodified. A byte-identical, signature-checked copy of its bundled backend is launched under a compatibility basename through CODEX_CLI_PATH. This does not disable monitoring, change system security, edit WindowsApps, migrate history, install services, or change system proxy/TUN settings. Do not infer unchanged monitoring coverage merely from unchanged settings.

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

The selected shortcut may be named **Tran (Codex7897)**. Back up its previous .lnk and preserve the original icon resource. Do not rewrite unrelated shortcuts or add login startup. Only one operator owns shortcut/receipt edits.

This isolated entrypoint does not automatically run the kit's optional Magpie or Orb hooks. Deployment must preserve and separately validate selected hooks rather than discard them, stack wrappers, or claim equivalent behavior. Do not replace an integrated shortcut until these choices are reconciled.

## Package identity and child environment

The entrypoint activates a hidden Windows PowerShell worker with Invoke-CommandInDesktopPackage and PreventBreakaway. The worker verifies its native package identity matches the selected installed version before launching the desktop. Proxy and backend environment overrides are set inside that worker for the desktop child; no global environment is changed. Chromium receives explicit proxy arguments.

PreventBreakaway affects the launched process tree. Validate terminal/tools and remote execution as well as native package/updater APIs before calling the deployment accepted. It does not prove Store connectivity or that an update can install. Package activation only reports package-launch-requested; do not equate this with a working desktop or remote connection.

## Update behavior

Each launch inventories the currently registered official package rather than hard-coding a WindowsApps version. Valid OpenAI signatures are required for the desktop and backend. The backend plus configured helpers are copied to a new version-and-content-addressed cache, verified against source SHA-256 values, and only then recorded in current.json. Previous manifest and prior caches remain. No running cached executable is overwritten; no old desktop is automatically paired with a new backend.

No network downloads or package updates are performed. Changed layout, missing helper, signature failure or cache mismatch stops launch and preserves data. Preparation is not compatibility acceptance: after every desktop update verify history loading, model reply, tools, remote executor registration and performance. Downgrading the installed package must be explicit and consider data compatibility.

## Validation status

Initial implementation is a review branch, not a released kit version. Before deployment, parse it on Windows, validate installed signature/layout and local profile with PrepareOnly, and run normal restart acceptance. Verify final process paths and proxy inheritance. A launch PID is not proof of remote connectivity. Keep sensitive logs, machine names, paths and binaries out of this repository.
