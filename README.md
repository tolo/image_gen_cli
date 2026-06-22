# image-gen

A Dart CLI that generates images with OpenAI's **`gpt-image-2`** model using
your **ChatGPT-subscription** credentials — reusing the OAuth tokens the Codex
CLI stores in `~/.codex/auth.json`. No billed API key required (though an
`sk-` key is supported as an alternate route).

## How it works (ChatGPT-subscription route)

Image generation is **not** a standalone endpoint on the ChatGPT backend
(`/codex/images/generations` returns 404). Instead it runs through the Codex
Responses endpoint using the built-in `image_generation` tool:

```
POST https://chatgpt.com/backend-api/codex/responses
  Authorization: Bearer <access_token>        # from ~/.codex/auth.json
  chatgpt-account-id: <account_id>
  originator: codex_cli_rs                     # required to clear Cloudflare
  OpenAI-Beta: responses=experimental
  Accept: text/event-stream

  { "model": "gpt-5.5",                         # a Codex-allowed *chat* model (carrier)
    "instructions": "You are an image generation assistant.",
    "input": [{ "role":"user", "content":[{"type":"input_text","text": <prompt>}] }],
    "tools": [{ "type":"image_generation",      # the image model lives HERE
                "model":"gpt-image-2", "size":"1024x1024", "quality":"medium",
                "output_format":"png", "background":"opaque" }],
    "tool_choice": { "type":"image_generation" }, "stream": true }
```

The response is an SSE stream; the final PNG arrives base64-encoded in the
`image_generation_call` item's `result`.

> **Carrier model drifts.** The top-level chat model accepted by the Codex
> backend for ChatGPT accounts changes over time (e.g. `gpt-5.5`). If you see
> *"model is not supported when using Codex"*, set a newer one via
> `--chat-model` or `$GPT_IMAGE_CHAT_MODEL`. This does **not** change the image
> model (`--model`, default `gpt-image-2`).

Requires a paid ChatGPT plan (Plus/Pro). Run `codex login` first so the
credentials exist. Tokens are refreshed automatically against
`https://auth.openai.com/oauth/token` when expired.

## Install

Prebuilt binaries are published for **macOS** (arm64/x64), **Linux** (arm64/x64),
and **Windows** (x64) on each [GitHub release](https://github.com/tolo/image_gen_cli/releases).

**Homebrew** (macOS / Linux):

```bash
brew install tolo/image-gen/image-gen
```

**Scoop** (Windows):

```powershell
scoop bucket add image-gen https://github.com/tolo/scoop-image-gen
scoop install image-gen
```

**Manual download:** grab the archive for your platform from the release page,
verify it against `SHA256SUMS.txt`, extract, and put `image-gen` on your `PATH`:

```bash
tar xzf image-gen-v<version>-<os>-<arch>.tar.gz     # .zip on Windows
sudo mv image-gen /usr/local/bin/
image-gen --version
```

**Build from source** (needs the Dart SDK `^3.6.0`):

```bash
cd ~/Repos/Tools/image_gen_cli
./build.sh                                           # compiles build/image-gen (native AOT)
ln -sf "$PWD/image-gen" /usr/local/bin/image-gen     # optional: put on PATH
```

The `image-gen` launcher runs the compiled binary if present, else `dart run`.
See [docs/RELEASING.md](docs/RELEASING.md) for how releases are cut.

## Usage

```bash
image-gen "a cute origami fox, flat vector, soft pastel colors" -a landscape -q medium -o fox.png

# Probe that generation is reachable with current credentials:
image-gen --check

# Force the official API-key route instead of the subscription:
image-gen "a logo" --api-key sk-... -m gpt-image-1
```

### Options

| Flag | Description | Values / default |
|------|-------------|------------------|
| `-p, --prompt` | Prompt (or pass positionally / via stdin) | |
| `-m, --model` | Image model | `gpt-image-2` (or `$GPT_IMAGE_MODEL`) |
| `--chat-model` | Carrier chat model (OAuth route; drifts) | `gpt-5.5` (or `$GPT_IMAGE_CHAT_MODEL`) |
| `-q, --quality` | Render quality | `low` `medium` `high` `auto` (default) |
| `-a, --aspect` | Aspect preset → fixed size | `square` `portrait` `landscape` `auto` |
| `-s, --size` | Explicit size (overrides `--aspect`) | `1024x1024` `1024x1536` `1536x1024` `auto` |
| `-b, --background` | Background handling | `transparent` `opaque` `auto` |
| `-f, --format` | Output format | `png` `jpeg` `webp` |
| `--n` | Number of images | `1` |
| `-o, --out` | Output file or base name | `image-<timestamp>` |
| `--auth-file` | Path to Codex `auth.json` | `~/.codex/auth.json` |
| `--api-key` | Use this API key (forces official API route) | |
| `--use-key` | Use the API key found in `auth.json`/env instead of OAuth | |
| `--check` | Probe reachability, then exit | |
| `-v, --verbose` | Verbose output | |
| `--version` | Print version, then exit | |

**Aspect → size mapping** (GPT-Image supports only fixed sizes, not free-form
aspect ratios): `square→1024x1024`, `portrait→1024x1536`,
`landscape→1536x1024`.

## Credential selection order

1. `--api-key sk-...`
2. `OPENAI_API_KEY` environment variable (only if `--use-key`, else OAuth wins)
3. `--use-key`: API key stored inside `auth.json`
4. **ChatGPT OAuth tokens in `auth.json`** (the default, working route)

## Two backends

| Route | Endpoint | Auth | Model param |
|-------|----------|------|-------------|
| **ChatGPT subscription** (default) | `…/codex/responses` + `image_generation` tool | Codex OAuth token | carrier `--chat-model` + image `--model` |
| OpenAI API key | `/v1/images/generations` | `sk-` key | single `--model` (use `gpt-image-1`) |

## Development

```bash
dart pub get
dart analyze
dart test
dart format --line-length=120 .
```

## Notes

This relies on the same first-party Codex transport the `codex` CLI uses
(including spoofing the `codex_cli_rs` originator to pass Cloudflare). The
Codex backend's accepted chat-model allow-list is undocumented and drifts;
`--chat-model` exists so you can track it without rebuilding.

## License

MIT — see [LICENSE](LICENSE).
