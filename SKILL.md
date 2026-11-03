---
name: codex-desktop-kit
description: Install, inspect, update or restore the Windows Codex Desktop Kit proxy shortcut and its optional Quota Orb and transport bridge components. Use for this suite, not generic VPN setup or every Codex connectivity issue.
---

# Codex Desktop Kit

Read the matching release's [installation guide](docs/installation.md) and [proxy/acceptance boundaries](docs/proxy-and-acceptance.md). Discover the user's actual proxy, Codex home, installed receipt and selected shortcuts before changing them.

For installation use `bootstrap.ps1` or `install.ps1`; for existing installs use the recorded package's `Test-Kit.ps1`, `update.ps1`, `restore.ps1` or `uninstall.ps1`. Runtime and component versions are pinned. Preserve existing settings and external work; a changed owned block/shortcut requires inspection, not force-overwrite.

The kit owns its final shortcut. Install the bridge with ComponentOnly and Quota Orb with NoShortcuts; do not stack wrappers. A separately running old orb is a global singleton, so verify executable path rather than assuming a new install switched the active version.

Never terminate the active Codex host. A normal user restart and actual model/tool request establish live acceptance; health/static checks and fixtures do not. Browser/MCP routing needs separate supported configuration. Keep credentials, machine paths and raw logs out of source and chat.

Maintenance responsibilities and source/document ownership are defined in [AGENTS.md](AGENTS.md) and [docs/maintenance.md](docs/maintenance.md).
