import 'dart:io';

import 'package:args/args.dart';

import 'package:image_gen_cli/src/codex_auth.dart';
import 'package:image_gen_cli/src/image_client.dart';
import 'package:image_gen_cli/src/version.dart';

const _aspectToSize = {
  'square': '1024x1024',
  'portrait': '1024x1536',
  'landscape': '1536x1024',
  'auto': 'auto',
};
const _validSizes = {'1024x1024', '1024x1536', '1536x1024', 'auto'};
const _validQuality = {'low', 'medium', 'high', 'auto'};
const _validBackground = {'transparent', 'opaque', 'auto'};
const _validFormat = {'png', 'jpeg', 'webp'};

Future<int> main(List<String> argv) async {
  final parser = _buildParser();
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    _printUsage(parser);
    return 64;
  }

  if (args.flag('help')) {
    _printUsage(parser);
    return 0;
  }

  if (args.flag('version')) {
    stdout.writeln('image-gen $imageGenVersion');
    return 0;
  }

  final verbose = args.flag('verbose');
  try {
    return await _run(args, parser, verbose: verbose);
  } on AuthException catch (e) {
    stderr.writeln('Auth error: ${e.message}');
    return 77;
  } on ImageApiException catch (e) {
    stderr.writeln('Generation failed: $e');
    if (e.modelUnsupported) {
      stderr.writeln(
        "The codex backend rejected the carrier chat model. Its allow-list "
        "drifts — try a newer --chat-model (e.g. gpt-5.5) or set "
        "\$GPT_IMAGE_CHAT_MODEL.",
      );
    } else if (e.forbidden) {
      stderr.writeln(
        'The ChatGPT route was challenged (403). Retry with --api-key '
        '<sk-...> or set OPENAI_API_KEY.',
      );
    }
    return 1;
  } catch (e) {
    stderr.writeln('Error: $e');
    return 1;
  }
}

Future<int> _run(ArgResults args, ArgParser parser, {required bool verbose}) async {
  // Resolve prompt: positional args, --prompt, or stdin.
  var prompt = (args.option('prompt') ?? args.rest.join(' ')).trim();
  if (prompt.isEmpty && !stdin.hasTerminal) {
    prompt = stdin.readLineSync()?.trim() ?? '';
  }
  final check = args.flag('check');
  if (prompt.isEmpty && !check) {
    stderr.writeln('No prompt given.');
    _printUsage(parser);
    return 64;
  }

  // Map aspect/size flags.
  var size = args.option('size');
  final aspect = args.option('aspect');
  if (size == null && aspect != null) size = _aspectToSize[aspect];
  size ??= '1024x1024';
  if (!_validSizes.contains(size)) {
    stderr.writeln('Invalid --size "$size". Valid: ${_validSizes.join(', ')}.');
    return 64;
  }

  final quality = args.option('quality')!;
  if (!_validQuality.contains(quality)) {
    stderr.writeln('Invalid --quality. Valid: ${_validQuality.join(', ')}.');
    return 64;
  }
  final background = args.option('background');
  if (background != null && !_validBackground.contains(background)) {
    stderr.writeln('Invalid --background. Valid: ${_validBackground.join(', ')}.');
    return 64;
  }
  final format = args.option('format');
  if (format != null && !_validFormat.contains(format)) {
    stderr.writeln('Invalid --format. Valid: ${_validFormat.join(', ')}.');
    return 64;
  }

  final n = int.tryParse(args.option('n')!) ?? 1;
  if (n < 1) {
    stderr.writeln('--n must be >= 1.');
    return 64;
  }

  final backend = await _selectBackend(args, verbose: verbose);

  final request = ImageRequest(
    prompt: check && prompt.isEmpty ? 'a small red dot on white' : prompt,
    model: args.option('model')!,
    size: check ? '1024x1024' : size,
    quality: check ? 'low' : quality,
    n: check ? 1 : n,
    background: background,
    outputFormat: format,
  );

  if (check) {
    stdout.writeln('Probing "${backend.label}" with a minimal request…');
    final imgs = await backend.generate(request);
    stdout.writeln('OK — image generation is reachable (${imgs.length} image).');
    return 0;
  }

  if (verbose) {
    stdout.writeln('Backend : ${backend.label}');
    stdout.writeln('Model   : ${request.model}');
    stdout.writeln('Size    : ${request.size}  Quality: ${request.quality}  N: ${request.n}');
  }
  stdout.writeln('Generating…');
  final images = await backend.generate(request);

  final paths = _resolveOutputPaths(args.option('out'), images);
  for (var i = 0; i < images.length; i++) {
    final file = File(paths[i]);
    if (file.parent.path.isNotEmpty) file.parent.createSync(recursive: true);
    await file.writeAsBytes(images[i].bytes);
    stdout.writeln('Saved ${file.path} (${images[i].bytes.length} bytes)');
  }
  return 0;
}

Future<ImageBackend> _selectBackend(ArgResults args, {required bool verbose}) async {
  // Explicit API key wins; then OPENAI_API_KEY env; then Codex credentials.
  final explicitKey = args.option('api-key');
  final envKey = Platform.environment['OPENAI_API_KEY'];
  if (explicitKey != null && explicitKey.isNotEmpty) {
    return ApiKeyBackend(explicitKey);
  }

  final creds = await CodexCredentials.load(args.option('auth-file'));
  if (args.flag('use-key')) {
    final key = creds.apiKey ?? envKey;
    if (key == null) throw AuthException('--use-key set but no API key found.');
    return ApiKeyBackend(key);
  }
  if (creds.hasOAuth) {
    if (verbose) stdout.writeln('Using Codex ChatGPT OAuth credentials.');
    return ChatGptOAuthBackend(creds, chatModel: args.option('chat-model')!);
  }
  final key = creds.apiKey ?? envKey;
  if (key != null) return ApiKeyBackend(key);
  throw AuthException(
    'No usable credentials. Run `codex login`, set OPENAI_API_KEY, '
    'or pass --api-key.',
  );
}

List<String> _resolveOutputPaths(String? out, List<GeneratedImage> images) {
  final base = out ?? 'image-${_timestamp()}';
  // If a single image and the base already has an extension, honour it.
  if (images.length == 1) {
    return [_hasExtension(base) ? base : '$base.${images.first.extension}'];
  }
  final stem = _hasExtension(base) ? base.substring(0, base.lastIndexOf('.')) : base;
  return [
    for (var i = 0; i < images.length; i++) '$stem-${i + 1}.${images[i].extension}',
  ];
}

bool _hasExtension(String p) {
  final slash = p.lastIndexOf(Platform.pathSeparator);
  final dot = p.lastIndexOf('.');
  return dot > slash && dot != p.length - 1;
}

String _timestamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}';
}

ArgParser _buildParser() {
  return ArgParser()
    ..addOption('prompt', abbr: 'p', help: 'Prompt text (or pass positionally / via stdin).')
    ..addOption('model',
        abbr: 'm',
        defaultsTo: Platform.environment['GPT_IMAGE_MODEL'] ?? 'gpt-image-2',
        help: 'Image model id. Default via \$GPT_IMAGE_MODEL or gpt-image-2.')
    ..addOption('chat-model',
        defaultsTo: Platform.environment['GPT_IMAGE_CHAT_MODEL'] ?? 'gpt-5.5',
        help: 'Carrier chat model for the ChatGPT-OAuth route (its allow-list '
            'drifts). Default via \$GPT_IMAGE_CHAT_MODEL or gpt-5.5.')
    ..addOption('quality', abbr: 'q', defaultsTo: 'auto', allowed: _validQuality, help: 'Render quality.')
    ..addOption('aspect', abbr: 'a', allowed: _aspectToSize.keys, help: 'Aspect preset (maps to a fixed size).')
    ..addOption('size', abbr: 's', help: 'Explicit size; overrides --aspect. One of: ${_validSizes.join(', ')}.')
    ..addOption('background', abbr: 'b', allowed: _validBackground, help: 'Background handling.')
    ..addOption('format', abbr: 'f', allowed: _validFormat, help: 'Output format (API-key route only; PNG otherwise).')
    ..addOption('n', defaultsTo: '1', help: 'Number of images to generate.')
    ..addOption('out', abbr: 'o', help: 'Output file or base name. Default: image-<timestamp>.')
    ..addOption('auth-file', help: 'Path to Codex auth.json. Default: ~/.codex/auth.json.')
    ..addOption('api-key', help: 'Use this OpenAI API key (forces the official API route).')
    ..addFlag('use-key', negatable: false, help: 'Use the API key found in auth.json / env instead of OAuth.')
    ..addFlag('check', negatable: false, help: 'Probe whether image generation is reachable, then exit.')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output.')
    ..addFlag('version', negatable: false, help: 'Print version and exit.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');
}

void _printUsage(ArgParser parser) {
  stdout.writeln('''
image-gen — generate images with OpenAI GPT-Image models

USAGE:
  image-gen [options] "your prompt here"
  image-gen -p "a watercolor fox" -a landscape -q high -o fox.png

Auth: reuses ChatGPT-subscription credentials from ~/.codex/auth.json by
default (run `codex login` first). Falls back to an OpenAI API key via
--api-key or the OPENAI_API_KEY env var.

OPTIONS:
${parser.usage}''');
}
