import 'dart:io';

/// Reads the `version:` field from pubspec.yaml without a YAML dependency.
///
/// Single source of truth for the release version. Used by [sync_version],
/// [build_release], and the packaging renderers, and runnable directly
/// (`dart run tool/read_version.dart`) to print the version for CI.
String readPubspecVersion([String? pubspecPath]) {
  final file = File(pubspecPath ?? 'pubspec.yaml');
  if (!file.existsSync()) {
    throw StateError('pubspec.yaml not found at ${file.path}');
  }
  for (final line in file.readAsLinesSync()) {
    final match = RegExp(r'^version:\s*([^\s#]+)').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  throw StateError('No `version:` field found in ${file.path}');
}

void main() {
  stdout.writeln(readPubspecVersion());
}
