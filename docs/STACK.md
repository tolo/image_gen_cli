# Technology Stack

## Languages
| Language | Version | Notes |
|----------|---------|-------|
| Dart     | SDK `^3.6.0` | Standalone CLI; AOT-compiled via `build.sh` to `build/image-gen` |

## Frameworks & Libraries
| Name   | Version  | Purpose |
|--------|----------|---------|
| `args` | `^2.6.0` | CLI argument parsing |
| `http` | `^1.2.0` | HTTP client for OpenAI/ChatGPT-Codex transports |
| `lints`| `^5.0.0` | Lint ruleset (dev) — see `analysis_options.yaml` (strict-casts + strict-raw-types) |
| `test` | `^1.25.0`| Test runner (dev); request-shape/decode tests use `MockClient` (no network) |

## External Services
| Service | Purpose | Docs |
|---------|---------|------|
| OpenAI `gpt-image-2` (default image model) via ChatGPT-subscription OAuth | Image generation through the Codex `/responses` transport (`image_generation` tool) | Unofficial first-party Codex transport — not officially supported |
| OpenAI Images API (`/v1/images/generations`) | API-key fallback route (`sk-` key) | https://platform.openai.com/docs |

## Credentials / Config
| Item | Location | Notes |
|------|----------|-------|
| ChatGPT OAuth tokens | `~/.codex/auth.json` | **Secret** — never log/print bearer. Refreshed + persisted atomically (mode 0600). Requires prior `codex login` |
| `$GPT_IMAGE_MODEL` / `$GPT_IMAGE_CHAT_MODEL` | env | Public interface; carrier chat model default `gpt-5.5` |

## Dev Tools
| Tool | Purpose | Config |
|------|---------|--------|
| `dart analyze` | Static analysis (must be clean) | `analysis_options.yaml` |
| `dart format --line-length=120` | Formatting | line length 120 |
| `dart test` | Unit tests (no network) | `test/` |
| `build.sh` | AOT compile → `build/image-gen` | — |

See `docs/KEY_DEVELOPMENT_COMMANDS.md` for command usage and `CLAUDE.md` for load-bearing transport facts.
