# Changes

## 0.1.7

- Magpie 重连遇到残留 Codex 进程时，先确认桌面已退出，再通过悬浮球的 `--exit` 正常释放其额度读取子进程，最多等待 5 秒。
- 仍有真正的 Codex CLI、桌面重新打开或清理失败时继续拒绝重连；已连接的聊天不触发清理。

## 0.1.4

- 固定桥接 1.5.2，将 HTTP 响应头等待期限从 60 秒放宽到 180 秒，减少长会话的过早重试。
- 升级继续保留现有组件选择、代理和快捷方式，旧桥接保留到现有会话退出。

## 0.1.3

- 固定 Quota Orb 0.1.12 及校验值，修正右键菜单空白图标栏，并支持在应用内单独开启外圈呼吸。

## 0.1.2

- 固定 Quota Orb 0.1.11 及 Release SHA-256，默认覆盖官方额度圆环，支持右键锁定、解锁和还原位置。
- 保留悬浮球大小选择及调节入口，沿用组件安装接口和套件管理的快捷方式。

## 0.1.1

- Wait for a matching Codex main window before starting Quota Orb, instead of treating successful Store activation as window readiness.
- Observe startup for at most 120 seconds and re-ensure the companion when a window/process is replaced during that period; do not stop Codex or install a permanent watcher.
- Add deterministic startup scenarios and a real delayed native-window fixture. Keep the standalone orb timeout and component versions unchanged.

## 0.1.0

- Initial dedicated proxy shortcut, optional components, pinned releases and transactional installation/restore workflow.
