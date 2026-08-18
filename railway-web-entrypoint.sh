#!/bin/sh
# Boot sequence for the Dify console + gateway service.
#
# Railway injects PORT into every service and it overrides whatever the image
# baked in. Here two processes want a port: nginx must take the injected one
# (Railway's healthcheck dials it, not the domain's target port), and the
# Next.js console has to be moved off it or the two collide.
set -eu

NGINX_PORT="${PORT:-8080}"
export NGINX_PORT
export PORT=3000
export HOSTNAME=127.0.0.1

: "${API_UPSTREAM:?API_UPSTREAM is required (http://<api-service>.railway.internal:5001)}"
: "${PLUGIN_UPSTREAM:=$API_UPSTREAM}"
export API_UPSTREAM PLUGIN_UPSTREAM
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-100M}"

# Re-resolving upstreams needs an explicit resolver; take the one the platform
# already gave the container rather than hardcoding a Railway address.
NGINX_RESOLVER="${NGINX_RESOLVER:-$(awk '/^nameserver/ {print ($2 ~ /:/) ? "["$2"]" : $2; exit}' /etc/resolv.conf)}"
NGINX_RESOLVER="${NGINX_RESOLVER:-127.0.0.11}"
export NGINX_RESOLVER

envsubst '${NGINX_PORT} ${NGINX_RESOLVER} ${API_UPSTREAM} ${PLUGIN_UPSTREAM} ${NGINX_CLIENT_MAX_BODY_SIZE}' \
  < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -t

echo "[railway] gateway on :$NGINX_PORT resolver=$NGINX_RESOLVER api=$API_UPSTREAM plugin=$PLUGIN_UPSTREAM"

(cd /app && su-exec dify /bin/sh /app/entrypoint.sh) &
WEB_PID=$!

nginx -g 'daemon off;' &
NGINX_PID=$!

wait -n 2>/dev/null || wait
echo "[railway] a gateway process exited; shutting the container down" >&2
kill -TERM "$WEB_PID" "$NGINX_PID" 2>/dev/null || true
exit 1
