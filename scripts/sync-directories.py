#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


REQUIRED_ENV = ("SSH_HOST", "SSH_PORT", "SSH_USER", "WP_PATH")
DEFAULT_EXCLUDES = (".user.ini",)
DEFAULT_IGNORE_FILE = ".wp-ssh-sync.ignore"


def fail(message: str) -> None:
    print(f"错误: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_env_file(path: Path) -> dict[str, str]:
    if not path.is_file():
        fail(f"未找到 .env 文件: {path}")

    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail(f"{path}:{line_number} 不是有效的 KEY=VALUE 格式")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            fail(f"{path}:{line_number} 缺少配置名")
        if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        values[key] = value
    return values


def collect_sync_maps(values: dict[str, str]) -> list[tuple[str, str, str]]:
    maps: list[tuple[str, str, str]] = []
    index = 1
    while True:
        key = f"SYNC_MAP_{index}"
        value = values.get(key)
        if value is None:
            break
        if ":" not in value:
            fail(f"{key} 必须使用 本地目录:远端目录 格式")
        local_raw, remote_raw = value.split(":", 1)
        local_raw = local_raw.strip()
        remote_raw = remote_raw.strip()
        if not local_raw or not remote_raw:
            fail(f"{key} 的本地目录和远端目录都不能为空")
        maps.append((key, local_raw, remote_raw))
        index += 1

    if not maps:
        fail("未配置任何 SYNC_MAP_1、SYNC_MAP_2... 同步目录映射")
    return maps


def normalize_relative(raw_path: str, label: str) -> Path:
    normalized = raw_path.strip().lstrip("/")
    if not normalized:
        fail(f"{label} 不能为空或仅为 /")
    path = Path(normalized)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        fail(f"{label} 只能是项目根或 WP_PATH 下的相对目录，不能包含 .. 或绝对路径: {raw_path}")
    return path


def remote_join(root: str, relative: Path) -> str:
    root = root.rstrip("/")
    if not root.startswith("/"):
        fail(f"WP_PATH 必须是远端绝对路径: {root}")
    return f"{root}/{relative.as_posix()}"


def build_ssh_parts(values: dict[str, str]) -> list[str]:
    ssh_parts = ["ssh", "-p", values["SSH_PORT"]]
    key_path = values.get("SSH_KEY_PATH", "").strip()
    if key_path:
        ssh_parts.extend(["-i", key_path, "-o", "IdentitiesOnly=yes"])
    extra_opts = values.get("SSH_EXTRA_OPTS", "").strip()
    if extra_opts:
        ssh_parts.extend(shlex.split(extra_opts))
    return ssh_parts


def resolve_ignore_file(project_root: Path, values: dict[str, str], explicit_ignore_file: str | None) -> Path | None:
    raw_ignore_file = explicit_ignore_file or values.get("SYNC_IGNORE_FILE", "").strip() or DEFAULT_IGNORE_FILE
    ignore_path = Path(raw_ignore_file)
    if not ignore_path.is_absolute():
        ignore_path = project_root / ignore_path
    if ignore_path.exists() and not ignore_path.is_file():
        fail(f"忽略规则路径不是文件: {ignore_path}")
    if ignore_path.is_file():
        return ignore_path
    return None


def run_sync(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).resolve()
    env_file = Path(args.env_file)
    if not env_file.is_absolute():
        env_file = project_root / env_file

    values = parse_env_file(env_file)
    missing = [key for key in REQUIRED_ENV if not values.get(key, "").strip()]
    if missing:
        fail(f".env 缺少必要配置: {', '.join(missing)}")

    if shutil.which("rsync") is None:
        fail("缺少 rsync 命令")
    if shutil.which("ssh") is None:
        fail("缺少 ssh 命令")

    sync_maps = collect_sync_maps(values)
    ignore_file = resolve_ignore_file(project_root, values, args.ignore_file)
    ssh_parts = build_ssh_parts(values)
    ssh_command = shlex.join(ssh_parts)
    ssh_target = f"{values['SSH_USER']}@{values['SSH_HOST']}"
    mode_label = "真实同步" if args.apply else "dry-run"

    print(f"wp-ssh-sync: {mode_label}，共 {len(sync_maps)} 个目录映射")
    if ignore_file is not None:
        print(f"wp-ssh-sync: 使用忽略规则文件 {ignore_file}")

    remote_rsync_check = [*ssh_parts, ssh_target, "command -v rsync >/dev/null 2>&1"]
    remote_rsync_completed = subprocess.run(remote_rsync_check, cwd=project_root)
    if remote_rsync_completed.returncode != 0:
        fail("远端服务器缺少 rsync 命令，无法执行 SSH/rsync 同步；请先在远端安装 rsync 后重试")

    for key, local_raw, remote_raw in sync_maps:
        local_rel = normalize_relative(local_raw, f"{key} 本地目录")
        remote_rel = normalize_relative(remote_raw, f"{key} 远端目录")
        local_dir = project_root / local_rel
        remote_dir = remote_join(values["WP_PATH"], remote_rel)

        if not local_dir.is_dir():
            fail(f"{key} 本地目录不存在: {local_dir}")

        if args.apply:
            mkdir_command = [*ssh_parts, ssh_target, f"mkdir -p -- {shlex.quote(remote_dir)}"]
            mkdir_completed = subprocess.run(mkdir_command, cwd=project_root)
            if mkdir_completed.returncode != 0:
                return mkdir_completed.returncode
        else:
            test_command = [*ssh_parts, ssh_target, f"test -d -- {shlex.quote(remote_dir)}"]
            test_completed = subprocess.run(test_command, cwd=project_root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if test_completed.returncode == 255:
                return test_completed.returncode
            if test_completed.returncode != 0:
                print(f"wp-ssh-sync: {key} 远端目录不存在，真实同步时会创建: {remote_dir}")
                continue

        command = [
            "rsync",
            "-az",
            "--itemize-changes",
            "--human-readable",
            "-e",
            ssh_command,
        ]
        if not args.apply:
            command.append("--dry-run")
        if args.delete:
            command.append("--delete")
        for exclude in DEFAULT_EXCLUDES:
            command.extend(["--exclude", exclude])
        if ignore_file is not None:
            command.extend(["--exclude-from", str(ignore_file)])
        command.extend([f"{local_dir}/", f"{ssh_target}:{shlex.quote(remote_dir + '/')}"])

        print(f"wp-ssh-sync: {key} {local_rel.as_posix()} -> {remote_dir}")
        completed = subprocess.run(command, cwd=project_root)
        if completed.returncode != 0:
            return completed.returncode
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="通过 SSH 和 rsync 同步已配置的 WordPress 目录。")
    parser.add_argument("--project-root", default=".", help="目标项目根目录。默认：当前目录。")
    parser.add_argument("--env-file", default=".env", help="项目本地 .env 文件。默认：.env。")
    parser.add_argument("--ignore-file", help="忽略规则文件。默认读取 .env 的 SYNC_IGNORE_FILE，未配置时使用 .wp-ssh-sync.ignore。")
    parser.add_argument("--apply", action="store_true", help="执行真实同步。不加此参数时，脚本使用 rsync --dry-run。")
    parser.add_argument("--delete", action="store_true", help="删除远端存在但本地已不存在的文件。")
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(run_sync(parse_args()))
