import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'read_version.dart';

/// Builds a release artifact for one target and writes its SHA-256 sidecar.
///
/// Pure Dart so it runs identically on macOS, Linux, and Windows CI runners.
/// Target is taken from `IMAGE_GEN_RELEASE_TARGET` (e.g. `linux-arm64`) and
/// defaults to the host. Linux arm64 is cross-compiled from x64; macOS and
/// Windows must build on a native runner of the matching arch.
///
/// Outputs into `build/`:
///   `image-gen-v<version>-<os>-<arch>.(tar.gz|zip)`
///   `image-gen-v<version>-<os>-<arch>.(tar.gz|zip).sha256`
Future<void> main() async {
  final version = readPubspecVersion();

  // Embed the version into the binary first.
  await _run('dart', ['run', 'tool/sync_version.dart']);

  final (hostOs, hostArch) = _hostTarget();
  final target = Platform.environment['IMAGE_GEN_RELEASE_TARGET'] ?? '$hostOs-$hostArch';
  final dash = target.lastIndexOf('-');
  if (dash < 0) throw ArgumentError('Malformed target "$target" (want <os>-<arch>)');
  final os = target.substring(0, dash);
  final arch = target.substring(dash + 1);

  final buildDir = Directory('build');
  if (buildDir.existsSync()) buildDir.deleteSync(recursive: true);
  final stage = Directory('build/stage')..createSync(recursive: true);

  final binName = os == 'windows' ? 'image-gen.exe' : 'image-gen';
  final binPath = '${stage.path}/$binName';

  final compileArgs = <String>['compile', 'exe', 'bin/image_gen.dart', '-o', binPath];
  if (os == 'linux') {
    // Dart cross-compiles arch within Linux from an x64 runner.
    compileArgs.addAll(['--target-os', 'linux', '--target-arch', arch]);
  } else if (os != hostOs || arch != hostArch) {
    throw StateError(
      'Target $os-$arch needs a native $os-$arch runner (host is $hostOs-$hostArch).',
    );
  }
  await _run('dart', compileArgs);

  // Stage docs alongside the binary.
  File('README.md').copySync('${stage.path}/README.md');
  File('LICENSE').copySync('${stage.path}/LICENSE');

  final base = 'image-gen-v$version-$os-$arch';
  final entries = [binName, 'README.md', 'LICENSE'];
  final archive = os == 'windows' ? 'build/$base.zip' : 'build/$base.tar.gz';
  if (os == 'windows') {
    await _zipWindows(stage.path, archive);
  } else {
    await _run('tar', ['-czf', archive, '-C', stage.path, ...entries]);
  }

  final digest = sha256.convert(File(archive).readAsBytesSync());
  final fileName = archive.split('/').last;
  File('$archive.sha256').writeAsStringSync('$digest  $fileName\n');

  stdout.writeln('Built $archive');
  stdout.writeln('       $archive.sha256');

  // Surface the version to GitHub Actions for downstream jobs.
  final ghOutput = Platform.environment['GITHUB_OUTPUT'];
  if (ghOutput != null) {
    File(ghOutput).writeAsStringSync('version=$version\n', mode: FileMode.append);
  }
}

(String, String) _hostTarget() {
  final abi = Abi.current();
  if (abi == Abi.macosArm64) return ('macos', 'arm64');
  if (abi == Abi.macosX64) return ('macos', 'x64');
  if (abi == Abi.linuxArm64) return ('linux', 'arm64');
  if (abi == Abi.linuxX64) return ('linux', 'x64');
  if (abi == Abi.windowsX64) return ('windows', 'x64');
  if (abi == Abi.windowsArm64) return ('windows', 'arm64');
  throw StateError('Unsupported host ABI: $abi');
}

Future<void> _zipWindows(String stageDir, String archive) async {
  // Compress-Archive is guaranteed present on Windows runners; zips the staged
  // files at archive root (no exec bit needed for .exe).
  await _run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "Compress-Archive -Path '$stageDir/*' -DestinationPath '$archive' -Force",
  ]);
}

Future<void> _run(String exe, List<String> args) async {
  stdout.writeln('\$ $exe ${args.join(' ')}');
  final result = await Process.start(exe, args, mode: ProcessStartMode.inheritStdio);
  final code = await result.exitCode;
  if (code != 0) {
    throw ProcessException(exe, args, 'exited with code $code', code);
  }
}
