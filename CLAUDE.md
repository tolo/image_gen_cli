# CLAUDE.md — image_gen_cli

Guidance for AI coding agents working in this repo. Global rules in `~/.claude/CLAUDE.md` still apply; this file is project-specific and wins on conflict.

## What this is

A standalone Dart CLI (`image-gen`) that generates images with OpenAI's **`gpt-image-2`** model by **reusing ChatGPT-subscription credentials** stored by the Codex CLI (`~/.codex/auth.json`). No billed API key required; an `sk-` key is supported as an alternate route. Package name: `image_gen_cli`. Binary/command: `image-gen`.

## Commands

```bash
dart pub get
dart analyze                                               # must be clean
dart format --line-length=120 --output=none --set-exit-if-changed .
dart test                                                  # 4 tests, no network (MockClient)
bash build.sh                                              # AOT-compile -> build/image-gen
./image-gen --check                                        # live reachability probe (needs creds)
```

The `./image-gen` launcher runs `build/image-gen` if present, else `dart run bin/image_gen.dart`. SDK: Dart `^3.6.0`.

## Layout

- `bin/image_gen.dart` — CLI: arg parsing (`args`), backend selection, aspect→size mapping, output-path resolution, error UX.
- `lib/src/codex_auth.dart` — `CodexCredentials`: load `auth.json`, JWT-exp check, OAuth refresh + atomic persist (mode 0600).
- `lib/src/image_client.dart` — two backends behind `ImageBackend`: `ChatGptOAuthBackend` (codex `/responses` + `image_generation` tool + SSE) and `ApiKeyBackend` (`/v1/images/generations`). `ImageApiException` exposes `unauthorized`/`forbidden`/`modelUnsupported`.
- `test/image_client_test.dart` — request-shape + decode tests via `MockClient`.
- `image-gen` (launcher), `build.sh` (AOT compile), `analysis_options.yaml` (lints + strict-casts/raw-types).

## Load-bearing facts — the whole design rests on these. Do not "fix" without re-verifying.

- **`gpt-image-2` is the real default image model.** It is NOT the top-level request model.
- **OAuth route mechanics** (the working, default path):
  - `POST https://chatgpt.com/backend-api/codex/responses` (SSE stream).
  - Top-level `model` is a **carrier chat model** (`gpt-5.5`), NOT an image model. The image model goes **inside** the `image_generation` tool with `tool_choice: {type: image_generation}`.
  - Required headers: `Authorization: Bearer <token>`, `chatgpt-account-id`, **`originator: codex_cli_rs`** + codex-shaped `User-Agent` (without the whitelisted originator Cloudflare returns 403), `OpenAI-Beta: responses=experimental`, `Accept: text/event-stream`.
  - Final PNG arrives base64 in the `image_generation_call` item's `result`.
  - Token refresh: `POST https://auth.openai.com/oauth/token`, `client_id app_EMoamEEZ73f0CkXaXp7hrann`, `grant_type refresh_token`; refreshed tokens persisted back to `auth.json` atomically.
- **Dead ends — do not retry:** `POST .../codex/images/generations` → 404 (no such endpoint). Image model name at top level → 400 "model is not supported when using Codex with a ChatGPT account". The codex `/responses` allow-list of chat models **drifts** — that is why `--chat-model` / `$GPT_IMAGE_CHAT_MODEL` exist (default `gpt-5.5`). When it drifts, bump the flag, do not rebuild.

## Conventions / constraints

- **`gpt-image-2`, `gpt-image-1` are OpenAI model IDs** — not the project name. Never rename them. Likewise the `$GPT_IMAGE_MODEL` / `$GPT_IMAGE_CHAT_MODEL` env vars are the tool's public interface.
- Aspect→size (GPT-Image has fixed sizes only): `square→1024x1024`, `portrait→1024x1536`, `landscape→1536x1024`, `auto→auto`. Quality: `low|medium|high|auto`. Background: `transparent|opaque|auto`.
- Credential order: `--api-key` → (`--use-key` ? key from auth.json/env) → **ChatGPT OAuth in auth.json (default)** → API key fallback.
- `~/.codex/auth.json` holds live OAuth tokens — **secret**. Never log the bearer; never print token contents.
- Format with `--line-length=120`. Keep `dart analyze` clean (strict-casts + strict-raw-types are on).
- This relies on the same unofficial first-party Codex transport `codex` uses (incl. the `codex_cli_rs` originator). Not officially supported; OpenAI could change/revoke it. Requires a paid ChatGPT plan and a prior `codex login`.

## Honesty

Verify changes against the real gates above before claiming done. The `--check` probe and any live image generation require valid credentials and hit the network — say so if you skip them.
