import 'dart:convert';
import 'dart:io';

import 'package:image_gen_cli/src/codex_auth.dart';
import 'package:image_gen_cli/src/image_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

ImageRequest _req() => ImageRequest(
      prompt: 'a red circle',
      model: 'gpt-image-1',
      size: '1024x1024',
      quality: 'low',
    );

void main() {
  group('ApiKeyBackend', () {
    test('sends auth header + body and decodes b64_json', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(utf8.encode('PNGBYTES'))},
            ],
          }),
          200,
        );
      });

      final images = await ApiKeyBackend('sk-test', client: mock).generate(_req());

      expect(captured.url.toString(), 'https://api.openai.com/v1/images/generations');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-image-1');
      expect(body['size'], '1024x1024');
      expect(images, hasLength(1));
      expect(utf8.decode(images.single.bytes), 'PNGBYTES');
    });

    test('surfaces API error message on non-2xx', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'error': {'message': 'bad prompt'},
            }),
            400,
          ));
      expect(
        () => ApiKeyBackend('sk-test', client: mock).generate(_req()),
        throwsA(isA<ImageApiException>().having((e) => e.message, 'message', contains('bad prompt'))),
      );
    });
  });

  group('ChatGptOAuthBackend', () {
    test('builds codex tool request and decodes image from the SSE stream', () async {
      final auth = await _writeOAuthAuthFile();
      final pngB64 = base64Encode(utf8.encode('PNGBYTES'));
      final sse = 'data: ${jsonEncode({
            'type': 'response.output_item.done',
            'item': {'type': 'image_generation_call', 'result': pngB64},
          })}\n'
          'data: [DONE]\n';
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(sse, 200);
      });
      final creds = await CodexCredentials.load(auth.path);

      final images = await ChatGptOAuthBackend(creds, chatModel: 'gpt-5.5', client: mock).generate(_req());

      expect(captured.url.toString(), 'https://chatgpt.com/backend-api/codex/responses');
      expect(captured.headers['Authorization'], 'Bearer opaque-token');
      expect(captured.headers['chatgpt-account-id'], 'acct-123');
      expect(captured.headers['originator'], 'codex_cli_rs');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-5.5'); // carrier chat model at top level
      expect(body['tool_choice'], {'type': 'image_generation'});
      final tool = (body['tools'] as List).single as Map<String, dynamic>;
      expect(tool['type'], 'image_generation');
      expect(tool['model'], 'gpt-image-1'); // image model lives in the tool
      expect(images, hasLength(1));
      expect(utf8.decode(images.single.bytes), 'PNGBYTES');

      auth.parent.deleteSync(recursive: true);
    });

    test('flags a drifted carrier model with an actionable error', () async {
      final auth = await _writeOAuthAuthFile();
      final mock = MockClient((req) async => http.Response(
            '{"detail":"The \'gpt-5.5\' model is not supported when using Codex with a ChatGPT account."}',
            400,
          ));
      final creds = await CodexCredentials.load(auth.path);

      await expectLater(
        ChatGptOAuthBackend(creds, chatModel: 'gpt-5.5', client: mock).generate(_req()),
        throwsA(isA<ImageApiException>().having((e) => e.modelUnsupported, 'modelUnsupported', isTrue)),
      );
      auth.parent.deleteSync(recursive: true);
    });
  });
}

/// Writes a throwaway auth.json with a non-JWT access token (so the expiry
/// check treats it as usable and no refresh is attempted).
Future<File> _writeOAuthAuthFile() async {
  final dir = Directory.systemTemp.createTempSync('gpt_image_auth');
  final file = File('${dir.path}/auth.json');
  await file.writeAsString(jsonEncode({
    'auth_mode': 'chatgpt',
    'OPENAI_API_KEY': null,
    'tokens': {
      'access_token': 'opaque-token',
      'refresh_token': 'refresh-123',
      'account_id': 'acct-123',
    },
  }));
  return file;
}
