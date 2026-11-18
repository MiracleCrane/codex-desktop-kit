# Codex Desktop Kit

给 Windows Codex 桌面端创建专用代理快捷方式，可选安装额度悬浮球和传输桥接。代理客户端提供本地 HTTP/mixed 端口即可；套件不会替你开启 TUN 或系统代理。

当前为 Windows x64 预览版，面向已安装并登录官方 Codex Desktop 的用户。本项目是非官方独立工具。

## 额度显示与悬浮球默认选择

默认不安装或随 Codex 启动 Quota Orb。使用 Magpie 时，请在 Magpie 中开启额度显示；本套件不会替你修改 Magpie 设置。Quota Orb 项目和可选能力继续保留，确实需要时显式传 `-WithQuotaOrb`，选装后仍提供自动启动与手动快捷方式。

此默认只适用于新的安装选择。更新会保留既有组件选择，不会删除悬浮球、终止进程或自动改写已有安装。已安装用户请先按安装文档核对所属入口，不要为此直接卸载组件。

当前 `main` 的安装器尚未包含其他分支的 Magpie 网关启动集成：它不能负责启动 Magpie，已有本地模型端点仍会按原保护逻辑拒绝安装。这里的额度显示建议不代表已合入 Magpie 或公司工作站兼容功能。
## 安装使用

1. 启动你的代理客户端，记下 HTTP/mixed 端口。
2. 下载本项目 Release ZIP 并解压，运行 `Install.cmd`。
3. 输入端口（例如 `7897`）或 `http://127.0.0.1:7897`，默认不安装或自动启动悬浮球；按需选择桥接。
4. 安装完成后，正常退出 Codex，再通过桌面或开始菜单的 **Codex (Proxy)** 打开。

选装悬浮球时，同目录还会提供 **Quota Orb** 手动开关；从其他入口打开 Codex 后，也可以手动开关球。

安装器优先复用合适的 PowerShell、Python；选择桥接时还会检查 Node.js。缺少的运行时从官方固定地址下载到套件目录，并核对固定 SHA-256，不修改系统 PATH。默认目录是 `%LOCALAPPDATA%\Programs\CodexDesktopKit`。

代理客户端仍需运行。每个人都可以填写自己的端口；悬浮球与桥接均可不选。已安装所需运行时的用户也可以直接运行：

```powershell
./install.ps1 -ProxyUri 'http://127.0.0.1:7897' -WithBridge
```

已有专用快捷方式时，可以传 `-ShortcutPath $existingLinks`，安装前保存其原始内容。没有明确选择的旧快捷方式不会被改动。依赖和参数细节见 [安装、更新与恢复](docs/installation.md)。

## 三个项目怎样配合

| 项目 | 职责 |
| --- | --- |
| 本项目 | 组合安装、代理配置、最终快捷方式、版本清单、集成验收 |
| [Quota Orb](https://github.com/MiracleCrane/quota-orb) | 悬浮球、额度读取、独立安装与生命周期 |
| [Codex Transport Bridge](https://github.com/MiracleCrane/codex-transport-bridge) | 模型传输桥接、独立安装、连接与配置回退 |

套件引用组件的固定 Release 和校验值，不复制组件源码。套件模式只由一个启动器打开 Codex，另外启动所选组件；组件不会再包装套件的快捷方式。悬浮球失败不阻挡 Codex。

## 检查、更新和卸载

```powershell
./Test-Kit.ps1 -InstallationPath $receiptPath
./update.ps1 -InstallationPath $receiptPath -PackageDirectory $newReleaseDirectory
./restore.ps1 -InstallationPath $receiptPath -WhatIf
./uninstall.ps1 -InstallationPath $receiptPath -WhatIf
```

`$receiptPath` 是安装目录中的 `installation.json`。更新保留当前组件选择与入口；改变组件选择时，先卸载原有集成，再重新安装。恢复和卸载只操作收据证明属于本次安装的配置与快捷方式，保留后来修改的无关内容。备份、下载缓存及可能仍在服务旧聊天的桥接文件保留，待确认无活动会话后再清理。

## 代理覆盖范围

启动器向桌面应用传代理参数，并在实际 Codex home 的 `.env` 中维护独立代理块，用于原生模型请求。同一 home 下的原生 Codex 入口也会读取这组值；它不是 Windows 全局代理设置。

浏览器、MCP、远程控制等辅助路径可能有各自的环境过滤或代理实现，需要独立核验。本项目不修改官方客户端源码、生成的插件清单、hosts 或证书。`Test-Kit` 的静态检查与真实的“关闭 TUN/系统代理后重启并完成模型回复”分开报告。见 [代理与验收边界](docs/proxy-and-acceptance.md)。

## 开发维护

源码与通用操作文档在所属项目维护；Agent 使用 [SKILL.md](SKILL.md) 作为短入口。仓库职责、组件升级次序、协作规则见 [AGENTS.md](AGENTS.md) 和 [维护安排](docs/maintenance.md)。

代码采用 [MIT](LICENSE)，运行时及组件保留自己的许可证，见 [THIRD_PARTY.md](THIRD_PARTY.md)。Codex 是 OpenAI 的产品名称。
