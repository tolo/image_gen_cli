import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'codex_auth.dart';

const _chatgptResponsesUrl = 'https://chatgpt.com/backend-api/codex/responses';
const _apiImagesUrl = 'https://api.openai.com/v1/images/generations';

/// `originator` must be a first-party value the Cloudflare layer in front of
/// the Codex backend whitelists, or the request is challenged (403) regardless
/// of auth. The codex CLI uses `codex_cli_rs`.
const _codexOriginator = 'codex_cli_rs';
const _codexUserAgent = 'codex_cli_rs/0.0.0 (image_gen_cli)';

/// A single generated image and the file extension implied by its format.
class GeneratedImage {
  GeneratedImage(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// Parameters for an image generation request, already validated/mapped from
/// CLI flags. [model] is the image model (e.g. `gpt-image-2`).
class ImageRequest {
  ImageRequest({
    required this.prompt,
    required this.model,
    required this.size,
    required this.quality,
    this.n = 1,
    this.background,
    this.outputFormat,
  });

  final String prompt;
  final String model;
  final String size; // 1024x1024 | 1024x1536 | 1536x1024 | auto
  final String quality; // low | medium | high | auto
  final int n;
  final String? background; // transparent | opaque | auto
  final String? outputFormat; // png | jpeg | webp
}

/// Raised on a non-2xx image response. [unauthorized] (401) means the token
/// should be refreshed; [modelUnsupported] flags the codex backend rejecting
/// the carrier chat model (its allow-list drifts over time).
class ImageApiException implements Exception {
  ImageApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  bool get unauthorized => statusCode == 401;
  bool get forbidden => statusCode == 403;
  bool get modelUnsupported => statusCode == 400 && message.contains('is not supported when using Codex');
  @override
  String toString() => 'Image API error ($statusCode): $message';
}

abstract class ImageBackend {
  String get label;
  Future<List<GeneratedImage>> generate(ImageRequest req);
}

/// Generates images via the public OpenAI API using an `sk-` key
/// (`/v1/images/generations`).
class ApiKeyBackend implements ImageBackend {
  ApiKeyBackend(this.apiKey, {http.Client? client}) : _client = client ?? http.Client();
  final String apiKey;
  final http.Client _client;

  @override
  String get label => 'OpenAI API key';

  @override
  Future<List<GeneratedImage>> generate(ImageRequest req) async {
    final body = <String, dynamic>{
      'model': req.model,
      'prompt': req.prompt,
      'n': req.n,
      'size': req.size,
      'quality': req.quality,
      if (req.background != null) 'background': req.background,
      if (req.outputFormat != null) 'output_format': req.outputFormat,
    };
    final resp = await _client.post(
      Uri.parse(_apiImagesUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'User-Agent': _codexUserAgent,
      },
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ImageApiException(resp.statusCode, _extractError(resp.body));
    }
    final json = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    final data = json['data'];
    if (data is! List || data.isEmpty) {
      throw ImageApiException(resp.statusCode, 'Response contained no image data.');
    }
    final fmt = req.outputFormat ?? 'png';
    final out = <GeneratedImage>[];
    for (final item in data.cast<Map<String, dynamic>>()) {
      final b64 = item['b64_json'];
      if (b64 is String) {
        out.add(GeneratedImage(base64Decode(b64), fmt));
      } else if (item['url'] is String) {
        out.add(GeneratedImage((await http.get(Uri.parse(item['url'] as String))).bodyBytes, fmt));
      }
    }
    return out;
  }
}

/// Generates images with the user's ChatGPT-subscription OAuth tokens via the
/// Codex Responses backend.
///
/// The top-level [chatModel] must be a codex-allowed *chat* model (its
/// allow-list drifts — `gpt-5.5` at time of writing); the image model goes
/// inside the `image_generation` tool. The response is a Server-Sent-Events
/// stream; the full image arrives base64-encoded in the
/// `image_generation_call` item's `result`. Refreshes the token once on a 401.
class ChatGptOAuthBackend implements ImageBackend {
  ChatGptOAuthBackend(this.creds, {required this.chatModel, http.Client? client}) : _client = client ?? http.Client();
  final CodexCredentials creds;
  final String chatModel;
  final http.Client _client;

  @override
  String get label => 'ChatGPT subscription (Codex OAuth)';

  @override
  Future<List<GeneratedImage>> generate(ImageRequest req) async {
    final out = <GeneratedImage>[];
    for (var i = 0; i < req.n; i++) {
      out.add(await _generateOne(req));
    }
    return out;
  }

  Future<GeneratedImage> _generateOne(ImageRequest req, {bool retried = false}) async {
    final token = await creds.validAccessToken();
    final body = <String, dynamic>{
      'model': chatModel,
      'instructions': 'You are an image generation assistant.',
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': req.prompt},
          ],
        },
      ],
      'tools': [
        <String, dynamic>{
          'type': 'image_generation',
          'model': req.model,
          'size': req.size,
          'quality': req.quality,
          if (req.outputFormat != null) 'output_format': req.outputFormat,
          if (req.background != null) 'background': req.background,
        },
      ],
      'tool_choice': {'type': 'image_generation'},
      'stream': true,
      'store': false,
    };
    final request = http.Request('POST', Uri.parse(_chatgptResponsesUrl))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'chatgpt-account-id': creds.accountId!,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'User-Agent': _codexUserAgent,
        'originator': _codexOriginator,
        'OpenAI-Beta': 'responses=experimental',
      })
      ..body = jsonEncode(body);

    final resp = await _client.send(request);
    if (resp.statusCode == 401 && !retried) {
      await resp.stream.drain<void>();
      await creds.refresh();
      return _generateOne(req, retried: true);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ImageApiException(resp.statusCode, _extractError(await resp.stream.bytesToString()));
    }

    final b64 = await _collectImage(resp.stream);
    if (b64 == null) {
      throw ImageApiException(resp.statusCode, 'Stream completed without an image.');
    }
    return GeneratedImage(base64Decode(b64), req.outputFormat ?? 'png');
  }

  /// Reads the SSE stream and returns the final image's base64, preferring the
  /// completed `image_generation_call.result` over any partial frames.
  static Future<String?> _collectImage(http.ByteStream stream) async {
    String? full;
    String? partial;
    await for (final line in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      final Map<String, dynamic> ev;
      try {
        ev = (jsonDecode(payload) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final item = ev['item'];
      if (item is Map && item['type'] == 'image_generation_call' && item['result'] is String) {
        full = item['result'] as String;
      } else if (ev['partial_image_b64'] is String) {
        partial = ev['partial_image_b64'] as String;
      }
    }
    return full ?? partial;
  }
}

String _extractError(String body) {
  try {
    final m = jsonDecode(body);
    if (m is Map) {
      if (m['error'] is Map) {
        final err = m['error'] as Map;
        return (err['message'] ?? err['code'] ?? body).toString();
      }
      if (m['detail'] != null) return m['detail'].toString();
    }
  } catch (_) {}
  return body.length > 400 ? '${body.substring(0, 400)}…' : body;
}
