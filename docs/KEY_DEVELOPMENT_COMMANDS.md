# Key Development Commands

## Setup
| Command | Description |
|---------|-------------|
| `dart pub get` | Install dependencies |

## Code Quality (Formatting, Linting)
| Command | Description |
|---------|-------------|
| `dart analyze` | Static analysis — **must be clean** (strict-casts + strict-raw-types on) |
| `dart format --line-length=120 --output=none --set-exit-if-changed .` | Verify formatting (line length 120) |

## Testing
| Command | Description |
|---------|-------------|
| `dart test` | Run all tests (4 tests, no network — `MockClient`) |
| `dart test test/image_client_test.dart -n "<name>"` | Run a single targeted test by name |

## Build & Run
| Command | Description |
|---------|-------------|
| `bash build.sh` | AOT-compile → `build/image-gen` |
| `./image-gen ...` | Launcher: runs `build/image-gen` if present, else `dart run bin/image_gen.dart` |
| `./image-gen --check` | Live reachability probe (needs valid credentials, hits network) |

> Credential order: `--api-key` → (`--use-key` + key from auth.json/env) → ChatGPT OAuth in `auth.json` (default) → API-key fallback. `--check` and real generation require valid credentials and network.
