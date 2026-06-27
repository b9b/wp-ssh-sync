---
name: wp-ssh-sync
description: 根据目标项目的本地配置和 SSH 凭据协调 WordPress SSH 同步流程。用于用户要求通过 SSH 和项目内目录映射同步 WordPress 文件、主题、插件、内容产物或部署资产的场景。
---

# wp-ssh-sync

基于目标项目 `.env` 中的目录映射执行 WordPress SSH 同步任务。

## 执行规则

- 将目标项目根目录作为凭据、状态、日志、临时文件和生成产物的边界。
- 除非用户明确提供其他安全来源，否则只从目标项目的 `.env` 文件读取连接配置。
- 只使用基于 SSH 的操作。不要发明 REST API、浏览器自动化或后台面板形式的回退路径。
- 真实同步必须使用确定性的内置脚本。目录同步入口是 `scripts/sync-directories.sh`。
- 同步脚本使用 `rsync` over SSH。默认执行真实同步，并带 `--delete --omit-dir-times`，使远端目录和本地目录保持一致，同时避免目录时间戳权限警告。
- 如果用户需要预览，显式添加 `--dry-run`；不要把 dry-run 当作默认行为。
- 执行真实同步前，先明确源目录、目标目录、同步方向，以及默认会删除远端多余文件。
- 目录同步时，按顺序读取 `SYNC_MAP_1`、`SYNC_MAP_2`、`SYNC_MAP_3` 等编号映射。每个值必须使用 `local_dir:remote_dir` 格式；本地路径相对目标项目根目录，远端路径相对 `WP_PATH`；任一侧开头的 `/` 仍表示对应根目录下的路径，不表示本机或服务器系统根目录。
- 默认读取目标项目根目录的 `.wp-ssh-sync.ignore` 作为忽略规则文件；如 `.env` 配置了 `SYNC_IGNORE_FILE` 或命令行传入 `--ignore-file`，使用对应文件。忽略规则交给 `rsync --exclude-from` 处理。
- 如果本机缺少 `rsync`，脚本会根据系统提示安装命令；如果远端缺少 `rsync`，直接报错并终止。

## 目标项目配置

至少验证目标项目 `.env` 中的这些配置：

```bash
SSH_HOST=example.com
SSH_PORT=22
SSH_USER=deploy
SSH_KEY_PATH=/Users/you/.ssh/id_ed25519
WP_PATH=/www/wwwroot/example.com
SYNC_MAP_1=/theme1:/theme1
# SYNC_MAP_2=/plugins/my-plugin:/wp-content/plugins/my-plugin
SYNC_IGNORE_FILE=.wp-ssh-sync.ignore
```

## 命令

预览同步：

```bash
scripts/sync-directories.sh --project-root /path/to/target-project --dry-run
```

执行真实同步。默认带 `--delete --omit-dir-times`：

```bash
scripts/sync-directories.sh --project-root /path/to/target-project
```
