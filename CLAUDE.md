# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Docker Compose stack — no application source code. It wires together Paperless-ngx (document
management) with its dependencies and an optional local-AI layer, all configured via per-service
`.env` files under a single `compose.yaml`. Changes here are almost always edits to `compose.yaml`
or a service's `.env` file, not code.

## Commands

```bash
docker compose up -d              # start the stack
docker compose down && docker compose up -d   # restart (compose restart does not reliably reload env changes)
docker compose pull && docker compose up -d   # update images
docker compose logs [service-name]            # tail logs for one service
docker compose ps                             # service status
```

There is no build, lint, or test step — validate changes by bringing the stack up and checking
`docker compose ps` / logs / the relevant service UI.

## Architecture

Services and how they depend on each other (see `compose.yaml`):

- **paperless** (port 8000) — core app (3.x). Depends on `postgres`, `redis`, `gotenberg`, `tika`.
  Requires `PAPERLESS_SECRET_KEY` in `paperless/.env` — startup aborts without it (new in 3.0).
  Ships built-in AI (suggestions + document chat) configured via the `PAPERLESS_AI_*` vars,
  pointed at `ollama`. It needs both a chat model (`PAPERLESS_AI_LLM_MODEL`) and an embedding
  model (`PAPERLESS_AI_LLM_EMBEDDING_MODEL`, defaults to `embeddinggemma`) pulled in Ollama.
  Because `ollama` is an internal compose hostname, `PAPERLESS_AI_LLM_ALLOW_INTERNAL_ENDPOINTS`
  must stay enabled.
- **postgres** — Paperless's database. `POSTGRES_DB`/`USER`/`PASSWORD` in `postgres/.env` must
  match `PAPERLESS_DBNAME`/`DBUSER`/`DBPASS` in `paperless/.env` — a common source of startup
  failures if changed inconsistently.
- **redis** — task queue/cache for Paperless.
- **gotenberg** — document conversion (used by Tika path); started with
  `--chromium-disable-javascript=true` and a restrictive `--chromium-allow-list`.
- **tika** — text extraction; Paperless reaches it via `PAPERLESS_TIKA_ENDPOINT` /
  `PAPERLESS_TIKA_GOTENBERG_ENDPOINT`.
- **ollama** — local LLM inference; reserves an NVIDIA GPU (`deploy.resources.reservations`).
  Comment out the `NVIDIA_*` vars in `ollama/.env` on non-GPU hosts.
- **open-webui** (port 3001) — UI for pulling/managing Ollama models; talks to `ollama` via
  `OLLAMA_BASE_URL`.
- **paperless-gpt** (port 3002, container port 8080) — vision-based OCR + metadata suggestions;
  also depends on `ollama` + `paperless` and uses a Paperless API token; prompt templates live in
  `paperless-gpt/prompts/` (mounted into the container).
- **dozzle** (port 8080) — log viewer; needs the Docker socket mounted read-write.

Cross-service contracts to keep in mind when editing `.env` files:
- Inter-container URLs use Docker service names (e.g. `http://paperless:8000`, `http://ollama:11434`), not `localhost`.
- `paperless-gpt` needs a Paperless API token, and every Ollama model name referenced in
  `paperless/.env` or `paperless-gpt/.env` must actually be pulled in Ollama (via Open WebUI or
  `docker exec ollama ollama pull <model>`) or those features fail to get responses.
- `paperless/.env` uses `KEY=value` syntax; `paperless-gpt/.env` uses `KEY: "value"` (YAML-style)
  — don't copy formatting between the two. Compose accepts both and strips inline `#` comments.

## Data and persistence

Each service's state lives in `./<service>/data` (bind-mounted), plus `./paperless/media`,
`./paperless/export`, and `./paperless/consume` for Paperless specifically. Documents are ingested
by dropping files into `./paperless/consume/`. Back up `paperless/data`, `paperless/media`, and
`postgres/data` before any destructive operation.

## Notes

- The AI stack (`ollama`, `open-webui`, `paperless-gpt`) is optional — comment those services out
  of `compose.yaml` and set `PAPERLESS_AI_ENABLED=0` to run Paperless alone.
- This stack is intended for local/VPN access only; services are not hardened for direct internet
  exposure.
