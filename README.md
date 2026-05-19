# Agent-OS Mac 安装器

这个仓库只做一件事：让普通 Mac 电脑可以傻瓜式安装 Agent-OS CLI。

安装脚本会自动处理：

- Node.js 和 npm
- Bun
- `@vionwilliams/agent-os`
- 终端 PATH 配置
- npm 专用缓存目录，避开旧 npm/sudo 造成的 `~/.npm` 权限问题
- 懒人快捷命令 `aos`
- 安装后的版本验证

DeepSeek 不在安装脚本里配置。正确流程是：先把 Agent-OS CLI 装好，顺利打开 `agent-os`，进入 Agent-OS 界面后再用 `/model` 配置 DeepSeek。

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

### 第 4 步：重启终端

关闭当前终端窗口，重新打开一个新的终端窗口。

### 第 5 步：验证安装结果

```bash
agent-os --version
```

成功时会看到类似：

```text
1.0.0-alpha.17 (Agent-OS)
```

### 第 6 步：打开 Agent-OS

```bash
agent-os
```

成功时会进入 Agent-OS 的 CLI 界面。

### 第 7 步：进入模型配置

在 Agent-OS 界面里输入：

```text
/model
```

如果首次打开时页面已经自动进入模型配置，就不用再输入 `/model`。

### 第 8 步：配置 DeepSeek

在模型配置界面选择或添加 DeepSeek，然后粘贴你的 DeepSeek API Key。

配置完成后，Agent-OS 才能正常回答问题。

### 第 9 步：测试是否能对话

回到 Agent-OS 对话界面，输入一句简单测试：

```text
回复 pong
```

如果能返回 `pong` 或正常回答，说明安装和 DeepSeek 配置都完成了。

## 常用命令

查看版本：

```bash
agent-os --version
```

查看帮助：

```bash
agent-os --help
```

短命令：

```bash
aos --help
```

## 关键说明

- 安装脚本只负责安装 CLI，不会在终端里询问 DeepSeek API Key。
- DeepSeek 配置在进入 Agent-OS 后完成，入口是 `/model`。
- `agent-os --version` 能显示版本，只代表 CLI 安装成功；能不能对话取决于是否已经在 `/model` 里配置模型。

## 以后升级 Agent-OS

```bash
npm install -g @vionwilliams/agent-os@alpha
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
- 正式命令是 `agent-os`，安装器会额外创建短命令 `aos`。
- 如果能看到版本号，但无法对话，优先检查 Provider 配置，不是安装失败。

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
