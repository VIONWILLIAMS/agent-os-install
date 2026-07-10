# Agent-OS Public Installer

这是 Agent-OS 的公开安装与原生 Release 仓库。产品源码可以保持私有；官网用户、安装器和自动升级器只访问这里。

## macOS / Linux

安装当前 beta：

```bash
curl -fsSL https://raw.githubusercontent.com/VIONWILLIAMS/agent-os-install/main/install.sh | bash -s -- --channel beta
```

安装指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/VIONWILLIAMS/agent-os-install/main/install.sh | bash -s -- --version 1.0.0-beta.3
```

默认安装在用户目录，不需要 Node.js、Bun、npm、`sudo` 或管理员权限：

- 程序版本：`~/.local/share/agent-os/versions/<version>`
- 当前版本：`~/.local/share/agent-os/current`
- 命令入口：`~/.local/bin/agent-os`
- 用户配置与数据库：`~/.agent-os`

## Windows PowerShell

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/VIONWILLIAMS/agent-os-install/main/install.ps1))) -Channel beta
```

安装指定版本：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/VIONWILLIAMS/agent-os-install/main/install.ps1))) -Version 1.0.0-beta.3
```

## 安装后

打开一个新终端并验证：

```bash
agent-os --version
agent-os update --check
```

常用生命周期命令：

```bash
agent-os update
agent-os update --channel beta
agent-os update --rollback
agent-os update --disable-auto-update
agent-os update --enable-auto-update
```

## 安全与更新合同

- 每个平台有独立原生压缩包和 `.sha256` 文件。
- 安装前校验 SHA-256，校验失败不会切换当前版本。
- 新版本先写入 staging，验证二进制与 UI 资源后再原子激活。
- 升级前会备份现有 coordination 数据库。
- 当前版本与上一版本保留，可执行 `agent-os update --rollback`。
- beta 与 stable 通道分离；未发布 stable 原生版前请使用 beta。

支持的平台：

- macOS Apple Silicon (`darwin-arm64`)
- macOS Intel (`darwin-x64`)
- Linux x64 (`linux-x64`)
- Linux ARM64 (`linux-arm64`)
- Windows x64 (`windows-x64`)

## npm 兼容安装

需要 npm 方式时仍可使用：

```bash
npm install -g @vionwilliams/agent-os@beta
```

npm 安装与原生安装可以共存。官网默认推荐原生安装，以避开 npm cache 权限、Node.js 版本和全局目录权限问题。
