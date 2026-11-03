# Changes

## 0.1.1

- Wait for a matching Codex main window before starting Quota Orb, instead of treating successful Store activation as window readiness.
- Observe startup for at most 120 seconds and re-ensure the companion when a window/process is replaced during that period; do not stop Codex or install a permanent watcher.
- Add deterministic startup scenarios and a real delayed native-window fixture. Keep the standalone orb timeout and component versions unchanged.

## 0.1.0

- Initial dedicated proxy shortcut, optional components, pinned releases and transactional installation/restore workflow.
