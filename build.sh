#!/usr/bin/env bash
# Compile image_gen_cli to a native AOT binary at build/image-gen.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

dart pub get
dart run tool/sync_version.dart
mkdir -p build
dart compile exe bin/image_gen.dart -o build/image-gen
echo "Built: $HERE/build/image-gen"
echo "Tip: symlink it onto your PATH, e.g."
echo "  ln -sf \"$HERE/image-gen\" /usr/local/bin/image-gen"
