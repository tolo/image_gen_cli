# Releasing image-gen

Cross-platform binaries (macOS arm64/x64, Linux arm64/x64, Windows x64) are
built and published by the `Release Binaries` GitHub Actions workflow, triggered
by pushing a `v*` tag.

## Cutting a release

1. Bump `version:` in `pubspec.yaml` and sync the embedded constant:
   ```bash
   dart run tool/sync_version.dart   # rewrites lib/src/version.dart
   ```
2. Commit both files.
3. Tag and push — **the tag must match the pubspec version** (the workflow fails
   otherwise):
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

The workflow then:

- builds a native binary per target (Linux arm64 is cross-compiled from x64;
  macOS/Windows build on native runners),
- uploads `image-gen-v<version>-<os>-<arch>.{tar.gz,zip}` + `.sha256` sidecars to
  the GitHub release,
- publishes an aggregate `SHA256SUMS.txt`,
- renders and pushes the Homebrew formula and Scoop manifest to their taps.

## One-time prerequisites

For Homebrew/Scoop publishing to work, create these **separately** (the
workflow skips them gracefully if the token is absent — GitHub-release assets
still publish):

| What | Where |
|------|-------|
| Homebrew tap repo | `github.com/tolo/homebrew-image-gen` (formula lands in `Formula/image-gen.rb`) |
| Scoop bucket repo | `github.com/tolo/scoop-image-gen` (manifest lands in `bucket/image-gen.json`) |
| `TAP_TOKEN` secret | A fine-grained PAT with **contents: write** on both tap repos, added as an Actions secret on this repo |

Repo names are configured via the `HOMEBREW_TAP_REPO` / `SCOOP_TAP_REPO` env
vars at the top of `.github/workflows/release-binaries.yml`.

## Local dry run

Build and inspect a single-target artifact without CI:

```bash
dart run tool/build_release.dart                       # builds for the host target
IMAGE_GEN_RELEASE_TARGET=linux-arm64 dart run tool/build_release.dart   # cross (Linux host only)
```

Artifacts land in `build/`. The renderers can be exercised against the produced
`.sha256` files via `tool/render_homebrew_formula.dart` and
`tool/render_scoop_manifest.dart`.
