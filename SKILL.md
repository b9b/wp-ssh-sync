---
name: wp-ssh-sync
description: Coordinate WordPress SSH synchronization workflows from a target project using SSH-based credentials and project-local configuration. Use when the user asks to sync WordPress files, content artifacts, or deployment assets over SSH; extend this scaffold with concrete scripts or references before running production sync operations.
---

# wp-ssh-sync

Use this skill for WordPress SSH synchronization tasks after the concrete sync workflow has been implemented in bundled scripts or references.

## Operating Rules

- Treat the target project root as the boundary for credentials, state, logs, temporary files, and generated artifacts.
- Read connection settings from the target project's `.env` file unless the user explicitly provides a different safe source.
- Use SSH-based operations only. Do not invent REST API, browser automation, or dashboard-based fallback paths.
- Prefer deterministic bundled scripts for real sync operations. If required scripts are not implemented yet, stop and explain what is missing instead of improvising against a live site.
- Before changing remote data, identify the source, destination, direction, and whether a dry run is available.
- Do not modify production data unless the user explicitly asks for a real sync and the required credentials/configuration are present.

## Expected Project Configuration

At minimum, future implementation should document and validate these target-project `.env` values:

```bash
SSH_HOST=example.com
SSH_PORT=22
SSH_USER=deploy
SSH_KEY_PATH=/Users/you/.ssh/id_ed25519
WP_PATH=/www/wwwroot/example.com
```

Add concrete commands, scripts, and safety checks as the SSH sync behavior becomes defined.
