import 'dart:io';

/// Renders a Scoop manifest (Windows) from the release checksum.
///
/// Usage:
///   `dart run tool/render_scoop_manifest.dart --version <v>`
///   `  --checksums-dir <dir> --repo <owner/repo> --output <path>`
void main(List<String> argv) {
  final opts = _parse(argv);
  final version = opts['version']!;
  final repo = opts['repo']!;
  final dir = opts['checksums-dir']!;
  final output = opts['output']!;

  final url = 'https://github.com/$repo/releases/download/v$version/image-gen-v$version-windows-x64.zip';
  final hash = _readSha('$dir/image-gen-v$version-windows-x64.zip.sha256');

  final manifest = '''
{
  "version": "$version",
  "description": "Generate images with OpenAI GPT-Image models via ChatGPT credentials",
  "homepage": "https://github.com/$repo",
  "license": "MIT",
  "architecture": {
    "64bit": {
      "url": "$url",
      "hash": "$hash"
    }
  },
  "bin": "image-gen.exe",
  "checkver": "github",
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/$repo/releases/download/v\$version/image-gen-v\$version-windows-x64.zip"
      }
    }
  }
}
''';

  File(output).writeAsStringSync(manifest);
  stdout.writeln('Wrote $output');
}

String _readSha(String path) {
  final file = File(path);
  if (!file.existsSync()) throw StateError('Missing checksum file: $path');
  return file.readAsStringSync().trim().split(RegExp(r'\s+')).first;
}

Map<String, String> _parse(List<String> argv) {
  final opts = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (arg.startsWith('--')) {
      final key = arg.substring(2);
      if (i + 1 >= argv.length) throw ArgumentError('Missing value for --$key');
      opts[key] = argv[++i];
    }
  }
  for (final required in ['version', 'repo', 'checksums-dir', 'output']) {
    if (!opts.containsKey(required)) throw ArgumentError('Missing --$required');
  }
  return opts;
}
