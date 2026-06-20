# wp-ssh-sync

`wp-ssh-sync` 是一个用于 WordPress SSH 同步的 AI Skill。它的同步能力应基于目标项目的 SSH 配置执行，适合把 WordPress 文件、内容产物或部署资产同步到远端站点。当前版本只提供基础 Skill 入口、安装方式和安全边界；具体同步动作会在后续版本通过脚本和规则补充。

这个 Skill 的约束是：同步能力应基于 SSH 和目标项目配置实现，不默认引入 REST API、后台表单、浏览器自动化或其他非 SSH 回退路径。

## 下载

推荐从 GitHub Releases 下载干净发布包。请下载 Release assets 里的 `wp-ssh-sync.zip` 或 `wp-ssh-sync.tar.gz`，不要使用 GitHub 自动生成的 `Source code` 包。

发布包解压后至少应得到这个结构：

```text
wp-ssh-sync/
├── SKILL.md
├── .env.example
└── agents/openai.yaml
```

后续版本加入具体同步能力时，发布包也可以包含 `scripts/`、`references/` 或 `assets/`。

## 一键安装

推荐使用 Release 里的 `install.sh` 一键安装。安装脚本会先判断目标目录是否存在，不存在再创建；如果已安装旧版本，默认会先备份旧目录再安装新版本。

```bash
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool codex --scope user
```

参数说明：

- `--tool codex|claude-code|opencode|all`：选择安装到哪个 AI 工具，默认 `codex`。
- `--scope user|project`：选择用户级还是项目级安装，默认 `user`。
- `--project /path/to/project`：项目级安装目标；未填写时使用当前目录。
- `--version v0.1.0`：安装指定 Release 版本；默认安装 latest。
- `--url URL`：从自定义 `wp-ssh-sync.zip` 地址安装。
- `--archive /path/to/wp-ssh-sync.zip`：从本地 zip 安装。
- `--install-dir /path/to/skills`：安装到自定义 skills 父目录，仅适合单个 `--tool`。
- `--no-backup`：不备份旧版本，直接替换。
- `--dry-run`：只打印将执行的安装动作，不写入文件。

如果你不喜欢 `curl | sh`，可以先下载再执行：

```bash
curl -fsSLO https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh
sh install.sh --tool codex --scope user
```

## Codex 安装

Codex 支持用户级 Skill 和项目级 Skill。用户级 Skill 对所有项目可用；项目级 Skill 只对当前仓库或工作目录可用。

### Codex 用户级安装

```bash
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool codex --scope user
```

安装后，在 Codex CLI、IDE extension 或 Codex app 中可以显式提到 `$wp-ssh-sync`，也可以让 Codex 根据任务自动选择它。

### Codex 项目级安装

先进入目标项目根目录，再执行项目级安装：

```bash
cd /path/to/target-project
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool codex --scope project
```

项目级安装适合团队共享。把 `.agents/skills/wp-ssh-sync/` 提交到目标项目后，团队成员在该项目中启动 Codex 即可使用。

## Claude Code 安装

Claude Code 支持个人 Skill 和项目 Skill。个人 Skill 位于 `~/.claude/skills/<skill-name>/SKILL.md`，项目 Skill 位于 `.claude/skills/<skill-name>/SKILL.md`。

### Claude Code 用户级安装

```bash
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool claude-code --scope user
```

使用时可以让 Claude Code 自动触发，也可以显式输入：

```text
/wp-ssh-sync
```

如果 Claude Code 会话已经启动，新增顶层 skills 目录后可能需要重启 Claude Code；已存在目录下的 `SKILL.md` 变更通常会被自动检测。

### Claude Code 项目级安装

```bash
cd /path/to/target-project
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool claude-code --scope project
```

项目级安装适合把这个 Skill 固定到某个 WordPress 项目中。

## OpenCode 安装

OpenCode 原生 Skill 位置是 `.opencode/skills/<name>/SKILL.md` 和 `~/.config/opencode/skills/<name>/SKILL.md`。它也会读取 `.claude/skills` 和 `.agents/skills` 兼容目录。

### OpenCode 用户级安装

```bash
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool opencode --scope user
```

### OpenCode 项目级安装

```bash
cd /path/to/target-project
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool opencode --scope project
```

如果你希望同一个项目目录同时被 Codex 和 OpenCode 发现，也可以把 Skill 安装到项目的 `.agents/skills`；OpenCode 会读取该兼容位置。

同时安装到三个工具：

```bash
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool all --scope user
```

项目级同时安装到三个工具：

```bash
cd /path/to/target-project
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh | sh -s -- --tool all --scope project
```

## 目标项目配置

无论这个 Skill 安装在全局目录还是项目目录中，真实连接凭据和同步状态都应该属于“被处理的目标项目”，而不是 Skill 安装目录。

在目标项目根目录创建 `.env`：

```bash
cd /path/to/target-project
if [ ! -f .env ]; then
  cp /path/to/wp-ssh-sync/.env.example .env
fi
```

至少填写：

```bash
SSH_HOST=example.com
SSH_PORT=22
SSH_USER=deploy
SSH_KEY_PATH=/Users/you/.ssh/id_ed25519
WP_PATH=/www/wwwroot/example.com
```

后续版本加入具体同步能力时，应在这里补充输入、输出、状态文件、dry-run 和真实执行命令的说明。

## AI 工具使用示例

Codex：

```text
使用 $wp-ssh-sync，根据 /path/to/target-project/.env 中的 SSH 配置，准备执行这个 WordPress 项目的同步流程。先说明将会读取哪些配置和需要哪些安全确认。
```

Claude Code：

```text
/wp-ssh-sync
请根据当前项目的 .env 检查 WordPress SSH 同步所需配置是否齐全。暂时不要执行真实同步。
```

OpenCode：

```text
Use the wp-ssh-sync skill to inspect the project SSH sync configuration and explain the next safe sync step.
```
