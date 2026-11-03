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

`CODEX_HOME` 沿用实际环境；没有设置时默认 `%USERPROFILE%\.codex`。不要把另一台电脑的路径或登录态复制过来。安装器检查本地代理，并合并现有内网绕过项；遇到 `NO_PROXY=*` 会停止，避免把绕过所有代理的配置当作成功。

## 安装后

安装不会结束当前 Codex。完成工作后正常退出，再从新入口打开。检查主程序、原生 app-server 的实际路径与代理连接，并完成一次模型回复及所需工具操作。应用重新加载前，原会话可能继续使用旧路由。

如果已有独立 Quota Orb 在运行，新组件的幂等启动会通知那个实例。需要切换版本时，先通过旧版本的 `--exit` 正常退出，核对旧 PID 消失，再通过桌面上下文启动新组件并核对可执行文件路径。无需退出 Codex 主程序。

## 更新与改变选择

更新从你已下载、核验的新套件 Release 执行。它保留代理、组件选择和原快捷方式列表：

```powershell
./update.ps1 -InstallationPath $receiptPath -PackageDirectory $newPackage
```

安装使用新的实例目录，不覆盖正在使用的二进制；上一次收据作为可回退版本保存。改变组件选择或所管理的快捷方式集合时，先 `uninstall.ps1` 恢复原有集成，再按新选择安装。不会静默取消桥接却留下旧模型端口。

## 恢复与卸载

`restore.ps1` 恢复当前安装拥有的代理块、桥接 URL 和快捷方式；升级后执行一次恢复会重新启用前一版的收据。`-AllVersions` 沿收据链恢复到最初状态。

```powershell
./restore.ps1 -InstallationPath $receiptPath -WhatIf
./restore.ps1 -InstallationPath $receiptPath -Confirm:$false
./uninstall.ps1 -InstallationPath $receiptPath -WhatIf
```

去掉卸载命令的 `-WhatIf` 执行实际卸载。卸载还调用 Quota Orb 自己的组件卸载入口，不处理另一份独立球的安装。备份、下载包、运行时和仍可能承接请求的旧桥接保留；不递归删除未知文件，也不结束 Codex。

安装、恢复、卸载按 Codex home 互斥。配置或入口被用户独立修改时，先停止并保留收据与备份供核对，不强制覆盖。不要手动修改收据来跳过冲突检查。
