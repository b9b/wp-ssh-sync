#!/bin/sh

if [ -n "${ZSH_VERSION:-}" ]; then
  emulate sh
fi
set -eu

PROJECT_ROOT="."
ENV_FILE=".env"
EXPLICIT_IGNORE_FILE=""
DRY_RUN="0"
DEFAULT_IGNORE_FILE=".wp-ssh-sync.ignore"

usage() {
  cat <<'HELP'
wp-ssh-sync directory sync

Usage:
  scripts/sync-directories.sh [options]

Options:
  --project-root PATH   Target project root. Default: current directory.
  --env-file PATH       Project .env file. Default: .env under project root.
  --ignore-file PATH    Override ignore file. Default: SYNC_IGNORE_FILE or .wp-ssh-sync.ignore.
  --dry-run             Preview rsync changes without writing remote files.
  -h, --help            Show this help.

Default behavior performs a real rsync over SSH with --delete and --omit-dir-times.
HELP
}

fail() {
  echo "错误: $*" >&2
  exit 1
}

log() {
  echo "wp-ssh-sync: $*"
}

trim() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

shell_quote() {
  awk -v value="$1" 'BEGIN {
    gsub(/\047/, "\047\\\047\047", value)
    printf "\047%s\047", value
  }'
}

install_hint() {
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "  brew install rsync"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "  sudo apt update && sudo apt install -y rsync openssh-client"
  elif command -v dnf >/dev/null 2>&1; then
    echo "  sudo dnf install -y rsync openssh-clients"
  elif command -v yum >/dev/null 2>&1; then
    echo "  sudo yum install -y rsync openssh-clients"
  elif command -v apk >/dev/null 2>&1; then
    echo "  sudo apk add rsync openssh-client"
  elif command -v pacman >/dev/null 2>&1; then
    echo "  sudo pacman -S --needed rsync openssh"
  else
    echo "  请使用当前系统的包管理器安装 rsync 和 OpenSSH client。"
  fi
}

need_local_commands() {
  missing=""
  command -v rsync >/dev/null 2>&1 || missing="rsync"
  command -v ssh >/dev/null 2>&1 || missing="${missing:+$missing }ssh"
  if [ -n "$missing" ]; then
    echo "错误: 本机缺少命令: $missing" >&2
    echo "可用的一键安装命令:" >&2
    install_hint >&2
    exit 1
  fi
}

parse_env_file() {
  [ -f "$ENV_FILE" ] || fail "未找到 .env 文件: ${ENV_FILE}"

  assignments=$(
    awk '
      function trim_value(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
      }
      function shell_quote_value(s) {
        gsub(/\047/, "\047\\\047\047", s)
        return "\047" s "\047"
      }
      {
        line = trim_value($0)
        if (line == "" || line ~ /^#/) {
          next
        }
        pos = index(line, "=")
        if (pos == 0) {
          printf("第 %d 行不是有效的 KEY=VALUE 格式\n", NR) > "/dev/stderr"
          exit 2
        }
        key = trim_value(substr(line, 1, pos - 1))
        value = trim_value(substr(line, pos + 1))
        if (key !~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
          printf("第 %d 行配置名无效: %s\n", NR, key) > "/dev/stderr"
          exit 2
        }
        if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
            (substr(value, 1, 1) == "\047" && substr(value, length(value), 1) == "\047")) {
          value = substr(value, 2, length(value) - 2)
        }
        print key "=" shell_quote_value(value)
      }
    ' "$ENV_FILE"
  ) || fail "解析 .env 失败: ${ENV_FILE}"

  eval "$assignments"
}

require_env() {
  missing=""
  [ -n "${SSH_HOST:-}" ] || missing="${missing:+$missing, }SSH_HOST"
  [ -n "${SSH_PORT:-}" ] || missing="${missing:+$missing, }SSH_PORT"
  [ -n "${SSH_USER:-}" ] || missing="${missing:+$missing, }SSH_USER"
  [ -n "${WP_PATH:-}" ] || missing="${missing:+$missing, }WP_PATH"
  [ -z "$missing" ] || fail ".env 缺少必要配置: $missing"

  case "$WP_PATH" in
    /*) ;;
    *) fail "WP_PATH 必须是远端绝对路径: ${WP_PATH}" ;;
  esac
}

normalize_relative() {
  raw=$(trim "$1")
  label="$2"
  while :; do
    case "$raw" in
      /*) raw=${raw#/} ;;
      *) break ;;
    esac
  done
  while :; do
    case "$raw" in
      */) raw=${raw%/} ;;
      *) break ;;
    esac
  done

  [ -n "$raw" ] || fail "${label} 不能为空或仅为 /"

  case "$raw" in
    "."|".."|./*|*/./*|*/.|../*|*/../*|*/..|*//*)
      fail "${label} 只能是相对目录，不能包含空路径、. 或 ..: ${raw}"
      ;;
  esac

  printf '%s\n' "$raw"
}

resolve_ignore_file() {
  raw_ignore="${EXPLICIT_IGNORE_FILE:-${SYNC_IGNORE_FILE:-$DEFAULT_IGNORE_FILE}}"
  raw_ignore=$(trim "$raw_ignore")
  [ -n "$raw_ignore" ] || return 0

  case "$raw_ignore" in
    /*) ignore_path="$raw_ignore" ;;
    *) ignore_path="$PROJECT_ROOT/$raw_ignore" ;;
  esac

  if [ -e "$ignore_path" ] && [ ! -f "$ignore_path" ]; then
    fail "忽略规则路径不是文件: ${ignore_path}"
  fi
  if [ -f "$ignore_path" ]; then
    printf '%s\n' "$ignore_path"
  fi
}

remote_ssh() {
  if [ -n "${SSH_KEY_PATH:-}" ]; then
    ssh -p "$SSH_PORT" -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes ${SSH_EXTRA_OPTS:-} "$SSH_TARGET" "$@"
  else
    ssh -p "$SSH_PORT" ${SSH_EXTRA_OPTS:-} "$SSH_TARGET" "$@"
  fi
}

build_rsync_ssh() {
  rsync_ssh="ssh -p $(shell_quote "$SSH_PORT")"
  if [ -n "${SSH_KEY_PATH:-}" ]; then
    rsync_ssh="$rsync_ssh -i $(shell_quote "$SSH_KEY_PATH") -o IdentitiesOnly=yes"
  fi
  if [ -n "${SSH_EXTRA_OPTS:-}" ]; then
    rsync_ssh="$rsync_ssh $SSH_EXTRA_OPTS"
  fi
  printf '%s\n' "$rsync_ssh"
}

run_sync_map() {
  key="$1"
  map_value="$2"

  case "$map_value" in
    *:*) ;;
    *) fail "${key} 必须使用 本地目录:远端目录 格式" ;;
  esac

  local_raw=${map_value%%:*}
  remote_raw=${map_value#*:}
  local_rel=$(normalize_relative "$local_raw" "$key 本地目录")
  remote_rel=$(normalize_relative "$remote_raw" "$key 远端目录")
  local_dir="$PROJECT_ROOT/$local_rel"
  remote_dir="${WP_PATH%/}/$remote_rel"

  [ -d "$local_dir" ] || fail "${key} 本地目录不存在: ${local_dir}"

  if [ "$DRY_RUN" = "1" ]; then
    if ! remote_ssh "test -d $(shell_quote "$remote_dir")"; then
      log "${key} 远端目录不存在，真实同步时会创建: ${remote_dir}"
      return 0
    fi
  else
    remote_ssh "mkdir -p $(shell_quote "$remote_dir")"
  fi

  log "${key} ${local_rel} -> ${remote_dir}"

  dry_run_flag=""
  [ "$DRY_RUN" = "0" ] || dry_run_flag="--dry-run"

  if [ -n "$IGNORE_FILE" ]; then
    rsync \
      -az \
      --delete \
      --omit-dir-times \
      --itemize-changes \
      --human-readable \
      $dry_run_flag \
      --exclude ".user.ini" \
      --exclude-from "$IGNORE_FILE" \
      -e "$RSYNC_SSH" \
      "$local_dir/" \
      "$SSH_TARGET:$(shell_quote "${remote_dir%/}/")"
  else
    rsync \
      -az \
      --delete \
      --omit-dir-times \
      --itemize-changes \
      --human-readable \
      $dry_run_flag \
      --exclude ".user.ini" \
      -e "$RSYNC_SSH" \
      "$local_dir/" \
      "$SSH_TARGET:$(shell_quote "${remote_dir%/}/")"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-root)
      [ "$#" -ge 2 ] || fail "--project-root 需要参数"
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --env-file)
      [ "$#" -ge 2 ] || fail "--env-file 需要参数"
      ENV_FILE="$2"
      shift 2
      ;;
    --ignore-file)
      [ "$#" -ge 2 ] || fail "--ignore-file 需要参数"
      EXPLICIT_IGNORE_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "未知参数: $1"
      ;;
  esac
done

[ -d "$PROJECT_ROOT" ] || fail "项目目录不存在: ${PROJECT_ROOT}"
PROJECT_ROOT=$(CDPATH= cd -- "$PROJECT_ROOT" && pwd)

case "$ENV_FILE" in
  /*) ;;
  *) ENV_FILE="$PROJECT_ROOT/$ENV_FILE" ;;
esac

need_local_commands
parse_env_file
require_env

SSH_TARGET="$SSH_USER@$SSH_HOST"
RSYNC_SSH=$(build_rsync_ssh)
IGNORE_FILE=$(resolve_ignore_file || true)

mode_label="真实同步"
[ "$DRY_RUN" = "0" ] || mode_label="dry-run"
log "${mode_label}，默认使用 rsync --delete --omit-dir-times"
if [ -n "$IGNORE_FILE" ]; then
  log "使用忽略规则文件 $IGNORE_FILE"
fi

if ! remote_ssh "command -v rsync >/dev/null 2>&1"; then
  fail "远端服务器缺少 rsync 命令，无法执行 SSH/rsync 同步；请先在远端安装 rsync 后重试"
fi

map_count=0
index=1
while :; do
  eval "map_value=\${SYNC_MAP_$index:-}"
  [ -n "$map_value" ] || break
  map_count=$((map_count + 1))
  run_sync_map "SYNC_MAP_$index" "$map_value"
  index=$((index + 1))
done

[ "$map_count" -gt 0 ] || fail "未配置任何 SYNC_MAP_1、SYNC_MAP_2... 同步目录映射"
