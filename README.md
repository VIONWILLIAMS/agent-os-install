# Agent-OS Mac 安装器

这个仓库只做一件事：让普通 Mac 电脑可以傻瓜式安装 Agent-OS CLI。

安装脚本会自动处理：

- Node.js 和 npm
- Bun
- `@vionwilliams/agent-os`
- 终端 PATH 配置
- npm 专用缓存目录，避开旧 npm/sudo 造成的 `~/.npm` 权限问题
- 懒人快捷命令 `aos`
- DeepSeek Provider 配置引导
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

也可以用短命令：

```bash
aos --help
```

如果能看到命令列表，说明 CLI 已经装好。

## Provider Setup

Agent-OS CLI 安装成功后，还需要配置一个模型 Provider。

如果没有配置 Provider，直接运行：

```bash
agent-os
```

可能会默认尝试连接 Anthropic，并出现：

```text
Unable to connect to Anthropic services
```

这不是安装失败，而是模型 Provider 没配置。

### 推荐：DeepSeek

重新运行最新版安装脚本时，它会提示：

```text
Configure DeepSeek now? [y/N]
```

输入 `y`，然后粘贴 DeepSeek API Key。脚本会自动写入：

```text
~/.agent-os/model-router.json
```

配置完成后再测试：

```bash
agent-os -p "回复 pong"
```

### 手动配置 DeepSeek

如果你想手动配置，执行：

```bash
mkdir -p ~/.agent-os
```

然后编辑：

```bash
nano ~/.agent-os/model-router.json
```

写入下面内容，并把 `sk-你的key` 换成真实 DeepSeek API Key：

```json
{
  "default": "deepseek/deepseek-v4-flash",
  "providers": {
    "deepseek": {
      "type": "deepseek",
      "baseUrl": "https://api.deepseek.com",
      "apiKey": "sk-你的key",
      "models": ["deepseek-v4-flash", "deepseek-v4-pro"]
    }
  }
}
```

保存后执行：

```bash
agent-os -p "回复 pong"
```

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
- 正式命令是 `agent-os`，安装器会额外创建短命令 `aos`。
- 如果看到 Anthropic 连接错误，优先检查 Provider 配置，不是安装失败。

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
