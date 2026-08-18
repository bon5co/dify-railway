# dify-railway

Wrapper images that make [Dify](https://github.com/langgenius/dify) 1.16.1 deployable on
Railway as a small, correctly-wired stack instead of the eleven-service compose translation
the marketplace currently ships.

| Image | Base | What the wrapper adds |
| --- | --- | --- |
| `ghcr.io/bon5co/dify-railway-api:1.16.1` | `langgenius/dify-api:1.16.1` | Runs the API, the Celery worker and beat in one container so they can share the storage volume (Railway volumes cannot be mounted by two services). Applies the schema migration exactly once, before any app process, instead of upstream's `MIGRATION_ENABLED=true` on both roles. Repairs the uid-0 volume mount and proves it is writable. Refuses to boot on an empty `SECRET_KEY`. Supervises all three roles. |
| `ghcr.io/bon5co/dify-railway-web:1.16.1` | `langgenius/dify-web:1.16.1` | Adds the nginx gateway from upstream's compose file into the same container, so the console, the API, the websocket and the plugin webhooks share one public origin — no second billed proxy service and no `CONSOLE_CORS_ALLOW_ORIGINS=*`. Moves Next.js off Railway's injected `PORT` and gives it to nginx, which is what the platform healthcheck dials. |
| `ghcr.io/bon5co/dify-railway-postgres:pg17` | `pgvector/pgvector:pg17` | Creates the plugin daemon's database, enables `vector` so the knowledge base needs no separate vector store, and sizes `shared_buffers`/`work_mem`/`effective_cache_size` from the container's cgroup limits. |

The Railway template spec that consumes these images lives in
[`railwaytemplate2`](https://github.com/bon5co/railwaytemplate2) as `scripts/specs/dify.json`,
with the competitive teardown in `dify/template.md`.
