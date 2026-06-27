# Repository Guidelines

## Project Structure & Module Organization

This repository develops the `wp-ssh-sync` AI Skill, not a target WordPress site. `SKILL.md` is the installable skill entrypoint and `agents/openai.yaml` stores tool metadata. Runtime sync logic lives in `scripts/sync-directories.sh`, which reads project `.env` files and runs `rsync` over SSH. `tools/build-release.py` builds clean release assets into `dist/`. Tests and fixtures live under `tests/`; `tests/fixtures/project/` contains sample WordPress themes and plugins for integration coverage. `README.md` is user-facing documentation, while `AGENT.md` records deeper maintenance and release notes.

## Build, Test, and Development Commands

- `python3 -B -m py_compile tools/build-release.py`: syntax-check the release builder.
- `sh -n install.sh`: validate installer shell syntax.
- `python3 -B tools/build-release.py`: rebuild `dist/wp-ssh-sync.zip`, `dist/wp-ssh-sync.tar.gz`, `install.sh`, and `SHA256SUMS`.
- `find scripts -name '*.sh' -print -exec sh -n {} \;`: syntax-check shell scripts.
- `sh tests/docker-sync-test.sh`: run the Docker SSH/rsync integration test when Docker is available.

## Coding Style & Naming Conventions

Keep sync scripts POSIX `sh` compatible so they run from bash, zsh, and plain sh. Use `set -eu`, quote paths carefully, and keep options long and descriptive, for example `--project-root` and `--dry-run`. Name sync configuration keys in uppercase, numbered form such as `SYNC_MAP_1`. Python remains acceptable for release tooling.

## Testing Guidelines

Add or update tests when changing sync behavior, ignore rules, installer behavior, or release packaging. Keep fixtures small and representative of WordPress themes/plugins. The Docker test must verify explicit `--dry-run`, default real sync with `--delete --omit-dir-times`, and excluded files such as `.user.ini`, `.DS_Store`, and `node_modules/`.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Implement SSH directory sync skill` and `Refine README user-facing intro`. Follow that style and keep each commit focused. Pull requests should describe user-visible behavior changes, list validation commands run, link related issues when applicable, and note any release-package impact.

## Security & Configuration Tips

Never commit `.env`, private keys, SSH local config, runtime logs, test runtime output, or generated `dist/` artifacts. Real credentials belong to the target project, not this skill repository. Default sync deletes remote-only files, so test changes with disposable targets before using production credentials.
