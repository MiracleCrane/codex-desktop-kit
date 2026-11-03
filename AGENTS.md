# Ownership and maintenance

This repository owns the combined installer, proxy launcher, component version pins, final kit shortcuts and integration acceptance. Do not copy bridge or Quota Orb implementation here. Changes to those components belong in their repositories and arrive as fixed releases with SHA-256 pins.

Use `docs/maintenance.md` for release order and Skill boundaries. During parallel work assign exactly one writer for installation receipts, active shortcuts and Codex configuration. Coordinate a component contract change with its consumer before publishing. Do not overwrite unrelated changes or force a shared branch.

Installation paths, proxies, account data, logs and config backups stay local. Preserve system-proxy/TUN mode, package identity, local/intranet bypasses and concurrent file edits. Never kill the active Codex host or tool transport for verification. Keep desktop GUI processes out of an Agent executor's lifetime when they must survive it.

Proxy-only installation must work without the optional components. An orb failure must not block the host. A bridge fallback must restore its owned configuration before host activation, with conflict checks; never leave a dead local URL while reporting a successful fallback.

Run affected launcher/configuration tests and installer upgrade/restore fixtures in external temporary directories. Integration fixtures use a fake Codex home and selected temporary shortcuts. No real model requests in CI. Real restart/network/model acceptance is separately recorded and must not be inferred from static checks.

README/docs are product instructions; SKILL.md is a short Agent operation entrypoint. Personal Skills retain routing and preferences, not copied code or a second manual. Publish from fixed commits; update runtime pins only from official sources and test their downloaded artifacts.
