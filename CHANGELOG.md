# Changes

## 0.1.2

- 固定 Quota Orb 0.1.11 及 Release SHA-256，默认覆盖官方额度圆环，支持右键锁定、解锁和还原位置。
- 保留悬浮球大小选择及调节入口，沿用组件安装接口和套件管理的快捷方式。

## 0.1.1

- Wait for a matching Codex main window before starting Quota Orb, instead of treating successful Store activation as window readiness.
- Observe startup for at most 120 seconds and re-ensure the companion when a window/process is replaced during that period; do not stop Codex or install a permanent watcher.
- Add deterministic startup scenarios and a real delayed native-window fixture. Keep the standalone orb timeout and component versions unchanged.

## 0.1.0

- Initial dedicated proxy shortcut, optional components, pinned releases and transactional installation/restore workflow.
