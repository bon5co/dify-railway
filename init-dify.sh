#!/bin/bash
# Runs once, on an empty data directory, from the stock postgres entrypoint.
set -euo pipefail

# A template publishes connection variables for its consumers, and those land in
# the environment of this script too. PGHOST in particular would send the psql
# below over the network to a database that is still initialising; the failure
# then restarts the container with PGDATA already present, so every init script
# is skipped and the service comes up healthy but unprovisioned.
export PGHOST=/var/run/postgresql
unset PGPASSWORD PGPORT PGHOSTADDR PGSERVICE PGSSLMODE || true

PLUGIN_DB="${DIFY_PLUGIN_DB:-dify_plugin}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
	CREATE EXTENSION IF NOT EXISTS vector;
SQL

if ! psql -tAc "SELECT 1 FROM pg_database WHERE datname='${PLUGIN_DB}'" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" | grep -q 1; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -c "CREATE DATABASE ${PLUGIN_DB}"
fi

# Size the server from the container's cgroup limits. Postgres' shipped
# defaults (128MB shared_buffers, 4MB work_mem, 64MB maintenance_work_mem) are
# what every competing Dify listing runs, whatever plan the deployer is on.
mem_max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
if [ "$mem_max" = "max" ] || [ -z "$mem_max" ]; then
  mem_max=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) * 1024 ))
fi
mem_mb=$(( mem_max / 1024 / 1024 ))
if [ "$mem_mb" -gt 512 ]; then
  shared_buffers=$(( mem_mb / 4 ))
  effective_cache=$(( mem_mb * 3 / 4 ))
  maintenance=$(( mem_mb / 16 ))
  [ "$maintenance" -gt 2048 ] && maintenance=2048
  work_mem=$(( mem_mb / 64 ))
  [ "$work_mem" -lt 4 ] && work_mem=4
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
	ALTER SYSTEM SET shared_buffers = '${shared_buffers}MB';
	ALTER SYSTEM SET effective_cache_size = '${effective_cache}MB';
	ALTER SYSTEM SET maintenance_work_mem = '${maintenance}MB';
	ALTER SYSTEM SET work_mem = '${work_mem}MB';
	ALTER SYSTEM SET max_connections = '200';
	SQL
  echo "[railway] sized postgres for ${mem_mb}MB: shared_buffers=${shared_buffers}MB work_mem=${work_mem}MB"
fi

echo "[railway] provisioned ${POSTGRES_DB} (pgvector) and ${PLUGIN_DB}"
