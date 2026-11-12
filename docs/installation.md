# 安装、更新与恢复

## 安装入口

普通安装：下载固定 Release，解压后运行 `Install.cmd`。系统自带 Windows PowerShell 5.1 负责引导；合适的运行时不存在时才下载到套件目录。运行时来源和摘要固定在 `runtimes.json`，组件固定在 `components.json`。下载始终走输入的本机代理，保留 TLS 校验，失败重试有上限，完整性校验失败不会执行。

系统执行策略阻止脚本时遵守设备策略；安装器不会关闭执行策略或提升权限。Windows x64、官方 Codex Desktop、.NET Framework 4.8 与已运行的 HTTP/mixed 代理是前提。高级命令入口要求 PowerShell 7.2+、Python 3.11+；桥接另需 Node.js 22+ 和 npm。

```powershell
./bootstrap.ps1 -ProxyUri 'http://127.0.0.1:7897' -WithQuotaOrb -WithBridge
./install.ps1 -Destination $directory -ProxyUri $proxyUri `
  -CodexHome $actualCodexHome -PythonPath $python -NodePath $node `
  -WithBridge -WithQuotaOrb -ShortcutPath $selectedExistingLinks
```

`-NoShortcuts` 可用于独立集成测试，禁止同时传 `-ShortcutPath`。默认新建桌面和开始菜单的 `Codex (Proxy)`；显式选定既有入口时，保存精确备份再切换。配置、收据、日志与运行时必须位于源码、Skill 发现目录和同步目录之外。

选择悬浮球时，安装器在所选 Codex 快捷方式所在目录创建或备份更新 `Quota Orb` 手动开关。它只切换球，不打开 Codex；由套件补齐所选 Codex home 与代理环境。传 `-NoQuotaShortcut` 可省略这个手动入口。

`CODEX_HOME` 沿用实际环境；没有设置时默认 `%USERPROFILE%\.codex`。不要把另一台电脑的路径或登录态复制过来。安装器检查本地代理，并合并现有内网绕过项；遇到 `NO_PROXY=*` 会停止，避免把绕过所有代理的配置当作成功。

## 安装后

安装不会结束当前 Codex。完成工作后正常退出，再从新入口打开。检查主程序、原生 app-server 的实际路径与代理连接，并完成一次模型回复及所需工具操作。应用重新加载前，原会话可能继续使用旧路由。

从 0.1.1 起，球的组合启动以实际主窗口就绪为条件。套件在发出 Codex 激活请求后最多观察 120 秒，使用应用身份而非激活返回的单个 PID 匹配窗口；窗口稳定 750 毫秒后调用 `--ensure-running`。启动期窗口消失或被替换后，会重新确认并启动球。窗口始终没有出现时记录超时并退出观察，不中止 Codex，也不反复重启它。球独立安装时的无宿主等待期限保持原组件契约。

如果已有独立 Quota Orb 在运行，新组件的幂等启动会通知那个实例。需要切换版本时，先通过旧版本的 `--exit` 正常退出，核对旧 PID 消失，再通过桌面上下文启动新组件并核对可执行文件路径。无需退出 Codex 主程序。

## 更新与改变选择

更新从你已下载、核验的新套件 Release 执行。它保留代理、组件选择和原快捷方式列表：

```powershell
./update.ps1 -InstallationPath $receiptPath -PackageDirectory $newPackage
```

安装使用新的实例目录，不覆盖正在使用的二进制；上一次收据作为可回退版本保存。改变组件选择或所管理的快捷方式集合时，先 `uninstall.ps1` 恢复原有集成，再按新选择安装。不会静默取消桥接却留下旧模型端口。

## 迁移到 Magpie 模式

Magpie 模式从 0.1.5 开始支持。先确保 Magpie 已保存供应商、账号和 Codex 接入，且当前 `openai_base_url` 是其本机 `/backend-api/codex` 地址；所引用的模型目录文件必须存在。套件不执行接入/断开或模型切换，这些操作可能使 Magpie 重启共享的 Codex app-server。

对已有多代桥接安装，先备份当前收据、模型配置和真正使用的快捷方式。使用现安装包的 `restore.ps1 -InstallationPath $receiptPath -AllVersions -Confirm:$false` 解除所有旧集成，再使用新包的 `install.ps1`，保留代理、实际 Codex home、原 `ShortcutPath` 和已选择的 `-WithQuotaOrb`，改传 `-MagpiePath` 与 `-MagpieBaseUrl`，不传 `-WithBridge`。不要在中间阶段激活被恢复出的旧入口；不要用 `uninstall.ps1` 顺便卸载仍需保留的 Orb。

所有恢复操作必须保留已经由 Magpie 接管的模型 URL；发生所有权冲突就检查，不强制覆盖。安装后收据与启动配置应包含 Magpie、没有 Bridge，后续 `update.ps1` 保留此选择。旧桥接文件和备份不删除。首次冷启动仍由用户正常退出/重开验收。

Magpie 未运行时，启动器以 `tray` 启动已选的本机程序，最多等待 30 秒。它使用 Magpie 已保存的网关配置，不重新配置供应商、不消耗模型额度来探活。网络代理、内网绕过和 `CODEX_HOME` 随启动过程传递；不会新建开机任务。服务身份与路由不匹配时不会激活 Codex，也不会自动恢复其他模型入口。

正常保存的网关配置会随 Magpie 启动；用户主动暂停或断开的状态不会被套件强行解除。已有 GUI 但网关暂时中断时会等待其自身恢复，超时则提示检查。启动前和网关就绪后都会重新核对模型入口，保留并行修改。

从 0.1.6 起可显式选择 `-ReconnectMagpie`：如果曾选择“断开 Codex 连接并退出”，且所有 Codex/ChatGPT 桌面及 CLI 进程都已退出，快捷方式会通过 Magpie 自己的 CLI 恢复接入，再启动网关和 Codex。已连接时不重复写入；有 Codex 进程时拒绝重连，以免共享 app-server 被结束。该选项不会改选另一供应商、添加回退、启用 credit 或取消主动暂停。它要求配置中有明确的当前模型，并保留该模型、推理档位、窗口及压缩设置；其他模型服务地址/自定义 provider 保持不动并提示人工检查。更新会保留这个选项。

## 恢复与卸载操作

`restore.ps1` 恢复当前安装拥有的代理块、桥接 URL 和快捷方式；升级后执行一次恢复会重新启用前一版的收据。`-AllVersions` 沿收据链恢复到最初状态。

```powershell
./restore.ps1 -InstallationPath $receiptPath -WhatIf
./restore.ps1 -InstallationPath $receiptPath -Confirm:$false
./uninstall.ps1 -InstallationPath $receiptPath -WhatIf
```

去掉卸载命令的 `-WhatIf` 执行实际卸载。卸载还调用 Quota Orb 自己的组件卸载入口，不处理另一份独立球的安装。备份、下载包、运行时和仍可能承接请求的旧桥接保留；不递归删除未知文件，也不结束 Codex。

安装、恢复、卸载按 Codex home 互斥。配置或入口被用户独立修改时，先停止并保留收据与备份供核对，不强制覆盖。不要手动修改收据来跳过冲突检查。
