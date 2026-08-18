#!/bin/bash
# Boot sequence for the combined Dify api + worker + beat service.
#
# Three things upstream's own entrypoint cannot do on Railway:
#   1. Repair ownership of the volume, which Railway mounts as uid 0 while the
#      image runs as the unprivileged "dify" user.
#   2. Run the schema migration exactly once. Upstream ships
#      MIGRATION_ENABLED=true on both the api and the worker container, so two
#      processes run alembic against one database on first boot.
#   3. Supervise the three roles, so that a dead worker restarts the service
#      instead of leaving a healthy-looking container with no job queue.
set -euo pipefail

STORAGE_ROOT="${OPENDAL_FS_ROOT:-/app/api/storage}"
PLUGIN_ROOT="${PLUGIN_STORAGE_LOCAL_ROOT:-}"

mkdir -p "$STORAGE_ROOT" /app/logs
chown -R dify:dify "$STORAGE_ROOT" /app/logs 2>/dev/null || true
echo "[railway] storage=$STORAGE_ROOT owner=$(stat -c %u:%g "$STORAGE_ROOT")"

# A Railway volume is a bind mount, so a write test is the only proof that the
# ownership repair worked; some apps merely log EACCES and keep serving.
if ! gosu dify test -w "$STORAGE_ROOT"; then
  echo "[railway] FATAL: $STORAGE_ROOT is not writable by the dify user" >&2
  exit 1
fi

if [ -z "${SECRET_KEY:-}" ]; then
  echo "[railway] FATAL: SECRET_KEY is empty. Refusing to boot: Dify signs" >&2
  echo "          session cookies and encrypts stored provider API keys with it." >&2
  exit 1
fi

export MIGRATION_ENABLED=false

echo "[railway] applying database migrations (once, before any app process)"
cd /app/api
gosu dify flask upgrade-db

start_role() {
  local role="$1"; shift
  echo "[railway] starting $role"
  MODE="$role" gosu dify /bin/bash /entrypoint.sh &
}

start_role worker
start_role beat
start_role api

# If any role dies, take the container down so Railway restarts it.
wait -n
echo "[railway] a Dify process exited; shutting the container down" >&2
kill -TERM 0 2>/dev/null || true
exit 1
