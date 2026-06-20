## 项目定位

这个仓库是`wp-ssh-sync`的Skill开发项目，不是最终安装目录。仓库中可以包含README、AGENT、测试、构建脚本和发布工作流；GitHub Release中的`wp-ssh-sync.zip`才是给AI工具安装的干净Skill包。

当前目标是先建立从开发到发布的通用流程，不实现具体SSH同步功能。后续开发具体同步能力时，再添加`scripts/`、`references/`或`assets/`。

## 必须遵守的规则

- README只写用户视角的Skill说明、安装方式、目标项目配置和AI工具使用方式，不写开发流水账。
- AGENT记录开发、测试、发布和维护流程。
- 不要提交`.env`、私钥、SSH本地配置、运行日志、测试运行产物或`dist/`发布产物。
- 真实连接凭据必须属于目标项目目录，不属于Skill安装目录。
- Release包必须保持干净，只包含可安装Skill所需文件，不包含测试数据、开发说明、GitHub工作流或仓库维护文件。
- 具体SSH同步逻辑必须通过明确的Skill说明和可验证脚本逐步加入；没有实现前，不要让Skill假装可以执行真实同步。

## 目录职责

- `SKILL.md`：Skill入口，包含`name`和`description`，以及AI执行该Skill时必须遵守的核心规则。
- `agents/openai.yaml`：Codex/OpenAI界面元数据。
- `.env.example`：目标项目`.env`模板，不包含真实凭据。
- `install.sh`：Release资产，一键安装到Codex、Claude Code、OpenCode的用户级或项目级Skill目录。
- `tools/build-release.py`：从仓库源码构建干净发布包。
- `.github/workflows/release.yml`：推送`v*` tag时自动创建GitHub Release并上传资产。
- `README.md`：用户使用说明。
- `AGENT.md`：开发和发布流程。

## 开发流程

1. 修改`SKILL.md`前，先确认`description`是否准确描述触发场景和边界。
2. 如果新增可复用命令，优先放入`scripts/`，并给脚本提供明确参数和失败退出行为。
3. 如果新增长说明或规则，优先放入`references/`，并在`SKILL.md`中说明什么时候读取。
4. 如果新增模板或静态资源，放入`assets/`。
5. 修改安装、使用方式或能力边界后，同步更新`README.md`。
6. 修改开发、测试、发布流程后，同步更新`AGENT.md`。

## 验证流程

每次提交前至少执行：

```bash
python3 -B -m py_compile tools/build-release.py
sh -n install.sh
python3 -B tools/build-release.py
```

如果后续新增脚本，同时执行：

```bash
find scripts -name '*.py' -print -exec python3 -B -m py_compile {} +
find scripts -name '*.sh' -print -exec sh -n {} \;
```

如本机有`skill-creator`官方校验脚本，也运行：

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py dist/wp-ssh-sync
```

如果校验脚本缺少`PyYAML`，可以在`/tmp`创建临时venv安装依赖，不要把临时依赖写入本仓库。

## 本地安装器测试

构建发布包后，用本地archive测试安装器，不要依赖还未发布的GitHub Release：

```bash
python3 -B tools/build-release.py
tmp_project="$(mktemp -d)"
sh install.sh --tool codex --scope project --project "$tmp_project" --archive dist/wp-ssh-sync.zip
test -f "$tmp_project/.agents/skills/wp-ssh-sync/SKILL.md"
```

测试`--dry-run`：

```bash
sh install.sh --tool all --scope project --project /tmp --archive dist/wp-ssh-sync.zip --dry-run
```

## 发布流程

1. 确认工作区干净，且没有`.env`、私钥、`dist/`或运行产物进入暂存区。
2. 执行验证流程。
3. 提交源码变更。
4. 推送`main`。
5. 创建并推送`v*`格式tag，例如：

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

GitHub Actions会自动执行验证、构建发布包，并上传这些Release assets：

- `install.sh`
- `wp-ssh-sync.zip`
- `wp-ssh-sync.tar.gz`
- `SHA256SUMS`

发布成功后，验证：

```bash
curl -fsSI https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh
curl -fsSL https://github.com/b9b/wp-ssh-sync/releases/latest/download/install.sh -o /tmp/wp-ssh-sync-install.sh
sh -n /tmp/wp-ssh-sync-install.sh
```

## GitHub仓库

远程仓库地址：

```bash
git@github.com:b9b/wp-ssh-sync.git
```

如仓库尚未初始化：

```bash
git init -b main
git remote add origin git@github.com:b9b/wp-ssh-sync.git
```
