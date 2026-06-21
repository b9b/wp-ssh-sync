#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_DIR="$ROOT_DIR/tests/runtime/docker-sync"
PROJECT_DIR="$RUNTIME_DIR/project"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures/project"
KEY_DIR="$RUNTIME_DIR/ssh"
CONTAINER_NAME="wp-ssh-sync-test-$$"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || {
  echo "错误: 缺少 docker" >&2
  exit 1
}

command -v ssh-keygen >/dev/null 2>&1 || {
  echo "错误: 缺少 ssh-keygen" >&2
  exit 1
}

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR" "$KEY_DIR"
cp -R "$FIXTURE_DIR" "$PROJECT_DIR"

ssh-keygen -q -t ed25519 -N "" -f "$KEY_DIR/id_ed25519"
chmod 600 "$KEY_DIR/id_ed25519"

docker run -d --name "$CONTAINER_NAME" -p 127.0.0.1::22 alpine:3.20 sleep 300 >/dev/null
docker exec "$CONTAINER_NAME" sh -c 'apk add --no-cache openssh rsync >/dev/null'
docker exec "$CONTAINER_NAME" sh -c 'adduser -D -h /home/deploy deploy && echo "deploy:test-only-password" | chpasswd && mkdir -p /home/deploy/.ssh /var/www/html && chown -R deploy:deploy /home/deploy /var/www/html'
docker cp "$KEY_DIR/id_ed25519.pub" "$CONTAINER_NAME:/home/deploy/.ssh/authorized_keys"
docker exec "$CONTAINER_NAME" sh -c 'chown deploy:deploy /home/deploy/.ssh/authorized_keys && chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys && ssh-keygen -A >/dev/null && /usr/sbin/sshd'

HOST_PORT=$(docker port "$CONTAINER_NAME" 22/tcp | sed 's/.*://')

attempt=1
while [ "$attempt" -le 30 ]; do
  if ssh -i "$KEY_DIR/id_ed25519" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p "$HOST_PORT" \
    deploy@127.0.0.1 true >/dev/null 2>&1; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 1
done

if [ "$attempt" -gt 30 ]; then
  echo "错误: Docker SSH 服务未就绪" >&2
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

cat > "$PROJECT_DIR/.env" <<EOF_ENV
SSH_HOST=127.0.0.1
SSH_PORT=$HOST_PORT
SSH_USER=deploy
SSH_KEY_PATH=$KEY_DIR/id_ed25519
SSH_EXTRA_OPTS=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
WP_PATH=/var/www/html
SYNC_MAP_1=themes/hello-elementor-child:wp-content/themes/hello-elementor-child
SYNC_MAP_2=plugins/jundongweb-elementor-extensions:wp-content/plugins/jundongweb-elementor-extensions
SYNC_MAP_3=plugins/jundongweb-acf-extensions:wp-content/plugins/jundongweb-acf-extensions
EOF_ENV

"$ROOT_DIR/scripts/sync-directories.sh" --project-root "$PROJECT_DIR"
"$ROOT_DIR/scripts/sync-directories.sh" --project-root "$PROJECT_DIR" --apply

docker exec "$CONTAINER_NAME" test -f /var/www/html/wp-content/themes/hello-elementor-child/style.css
docker exec "$CONTAINER_NAME" test -f /var/www/html/wp-content/plugins/jundongweb-elementor-extensions/plugin.php
docker exec "$CONTAINER_NAME" test -f /var/www/html/wp-content/plugins/jundongweb-acf-extensions/plugin.php
if docker exec "$CONTAINER_NAME" test -e /var/www/html/wp-content/themes/hello-elementor-child/.user.ini; then
  echo "错误: .user.ini 不应被同步" >&2
  exit 1
fi
if docker exec "$CONTAINER_NAME" test -e /var/www/html/wp-content/themes/hello-elementor-child/.DS_Store; then
  echo "错误: .DS_Store 不应被同步" >&2
  exit 1
fi
if docker exec "$CONTAINER_NAME" test -e /var/www/html/wp-content/themes/hello-elementor-child/node_modules; then
  echo "错误: node_modules 不应被同步" >&2
  exit 1
fi
if docker exec "$CONTAINER_NAME" test -e /var/www/html/wp-content/plugins/jundongweb-elementor-extensions/debug.local; then
  echo "错误: *.local 不应被同步" >&2
  exit 1
fi

echo "docker sync test passed"
