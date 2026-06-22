# Project Learnings

> Defensive knowledge for future contributors — traps and error patterns. `LEARNINGS = "watch out for X"`; choices-with-rationale belong in load-bearing facts in `CLAUDE.md`. The authoritative transport facts live in **`CLAUDE.md` → "Load-bearing facts"** — this file holds the "do not retry" traps for quick recall.

## OpenAI / Codex Transport
<!-- Append via the `andthen:ops` skill (`update-learnings add` form). -->

- **Image model name at top level → 400.** The top-level `model` must be a *carrier chat model* (`gpt-5.5`); the image model (`gpt-image-2`) goes *inside* the `image_generation` tool with `tool_choice: {type: image_generation}`.
- **Missing `originator: codex_cli_rs` → 403.** Cloudflare rejects the request without the whitelisted originator + codex-shaped `User-Agent`.
- **`POST .../codex/images/generations` → 404.** No such endpoint — do not retry; use `/codex/responses` (SSE).
- **Codex `/responses` chat-model allow-list drifts.** When `gpt-5.5` stops working, bump `--chat-model` / `$GPT_IMAGE_CHAT_MODEL` — do **not** rebuild the transport.

## Error Patterns
| Error | Type | Conclusion |
|-------|------|------------|
| 403 from Cloudflare on `/responses` | Deterministic | Missing/incorrect `originator` or `User-Agent` header |
| 400 "model is not supported when using Codex with a ChatGPT account" | Deterministic | Image model placed at top level instead of in the tool |
