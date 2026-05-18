# Agent-OS Mac 安装器

这个仓库只做一件事：让普通 Mac 电脑可以傻瓜式安装 Agent-OS CLI。

安装脚本会自动处理：

- Node.js 和 npm
- Bun
- `@vionwilliams/agent-os`
- 终端 PATH 配置
- npm 专用缓存目录，避开旧 npm/sudo 造成的 `~/.npm` 权限问题
- 安装后的版本验证

## 最懒人安装

### 第 1 步：打开终端

打开 Mac 自带的 Terminal，或者 iTerm2。

### 第 2 步：下载安装脚本

```bash
curl -fsSL https://raw.githubusercontent.com/VIONWILLIAMS/agent-os-install/main/install-macos-cli.sh -o install-agent-os-mac.sh
```

### 第 3 步：运行安装脚本

```bash
bash install-agent-os-mac.sh
```

### 第 4 步：验证安装结果

```bash
agent-os --version
```

成功时会看到类似：

```text
1.0.0-alpha.12 (Agent-OS)
```

### 第 5 步：查看 Agent-OS 命令

```bash
agent-os --help
```

如果能看到命令列表，说明 CLI 已经装好。

## 以后升级 Agent-OS

```bash
npm install -g @vionwilliams/agent-os@latest
```

然后验证：

```bash
agent-os --version
```

## 说明

- 这个安装器只支持 macOS。
- Agent-OS CLI 本体来自 npm 包：`@vionwilliams/agent-os`。
- 用户不需要 clone Agent-OS 源码仓库。
- 安装器默认使用 `~/.agent-os/npm-cache` 作为 npm 缓存，不依赖 `~/.npm`。

## 常见问题

### npm 报 EACCES / root-owned cache

如果你看到类似错误：

```text
Your cache folder contains root-owned files
path /Users/xxx/.npm/_cacache
```

请重新下载并运行最新版安装脚本。新版脚本会自动使用 Agent-OS 专用 npm 缓存：

```text
~/.agent-os/npm-cache
```

不需要手动修改 `~/.npm`。
