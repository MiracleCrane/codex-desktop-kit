# 代理实现与验收边界

## 三条路径

1. Chromium 桌面请求：正常 Windows Store 应用激活时传入 `--proxy-server` 与本地/内网绕过列表，保留应用身份。
2. 原生 Codex 请求：在实际 Codex home 的 `.env` 维护五个代理环境字段的独立块；其他内容原样保留。该范围包括使用同一 home 的原生入口。
3. 辅助工具：浏览器、MCP、远程控制等可能有自己的环境过滤或 Node 网络路径，需要按对应工具支持的配置单独验证。

启动器也设置自身 Process 环境，但 Store 激活接口不接受显式环境块，因此不能只凭启动器变量证明新进程继承。原生入口加载 `.env` 的依据见 [Codex arg0 源码](https://github.com/openai/codex/blob/main/codex-rs/arg0/src/lib.rs)；Store 激活接口见 [微软文档](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iapplicationactivationmanager-activateapplication)。版本更新后应重新核对实际行为。

套件不改 Windows User/Machine 代理变量、系统代理、TUN、hosts、证书或官方客户端代码。`.env` 支持大小写混用的代理键，并保留已有 NO_PROXY 内网条目。无法可靠理解的现有表达式会停止，留给用户检查。

## 自动检查

`Test-Kit.ps1` 核对安装收据、启动器哈希、快捷方式、代理监听、代理块的实际有效值、模型路由类别、桥接实例身份以及悬浮球状态。错误/缺失状态不能解释为已运行。

配置事务、升级回退、启动器协调和故障夹具不会发送模型请求。它们不能代替真实桌面重启，也不能证明所有插件的网络能力。

## 真实验收

保留用户选定的代理模式，在系统代理与 TUN 关闭时，通过正常快捷方式启动新的 Codex 进程；核对桌面与 app-server 的实际代理连接、模型回复和工具往返。打开页面或监听端口都不足以代替模型链路。

不要为验收结束承载当前任务的 Codex。先完成准备，由用户正常退出/重开后继续核对。在新进程、配置、连接与真实结果全部确认之前，收据的 ColdRestartVerified / SystemProxyTunOffVerified 保持 false。远程控制、浏览器与 MCP 分别记录自己的通过情况。

悬浮球启动失败不应阻止 Codex。桥接无法就绪时，仅在其拥有的配置可恢复到原默认上游时自动回退；若原配置还指向另一个桥接或存在冲突，就停止该次启动并提示检查，避免留下看似打开、实际全走失效端口的状态。
