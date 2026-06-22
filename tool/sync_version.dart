import 'dart:io';

import 'read_version.dart';

/// Regenerates `lib/src/version.dart` from the pubspec version so the compiled
/// binary can report it via `--version`. Idempotent; run before every build.
void main() {
  final version = readPubspecVersion();
  final out = File('lib/src/version.dart');
  final contents = "// GENERATED — do not edit by hand.\n"
      "// Kept in lockstep with pubspec.yaml by `dart run tool/sync_version.dart`.\n"
      "const imageGenVersion = '$version';\n";
  if (out.existsSync() && out.readAsStringSync() == contents) {
    stdout.writeln('version.dart already current ($version)');
    return;
  }
  out.writeAsStringSync(contents);
  stdout.writeln('Wrote lib/src/version.dart ($version)');
}
