# Third-party components and runtimes

Quota Orb and Codex Transport Bridge are separately maintained MIT projects. Their exact release assets and SHA-256 values are pinned in `components.json`; installed packages retain their license files.

Bootstrap downloads official runtime ZIPs only when needed: PowerShell (MIT), Node.js (its bundled licenses) and Python (PSF license and bundled notices). `runtimes.json` records the official source and trusted SHA-256. These binaries are not included in the kit source release; downloaded distributions retain their upstream notices. No official Codex executable, brand asset, login file or account data is redistributed.

The launcher uses Windows and .NET Framework APIs. The Codex desktop application and local proxy software are installed and managed separately by the user.
