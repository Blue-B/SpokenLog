import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voice_transcriber/models/transcription_error.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/services/cloud_request.dart';
import 'package:voice_transcriber/services/cloudflare_transcription_service.dart';
import 'package:voice_transcriber/services/groq_transcription_service.dart';

import 'release_safety_test.dart' as fixtures;

class TrackingClient extends MockClient {
  TrackingClient(super.handler);
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  for (final stallBody in [false, true]) {
    test(
      'real HTTP timeout covers stalled ${stallBody ? 'body' : 'headers'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<void>();
        server.listen((request) {
          received.complete();
          unawaited(request.drain<void>().catchError((Object error) {}));
          if (stallBody) {
            request.response.headers.contentType = ContentType.json;
            request.response.write('{');
            unawaited(request.response.flush().catchError((Object error) {}));
          }
          // Deliberately leave the response incomplete, as a stalled proxy can.
        });
        try {
          final request = http.Request(
            'POST',
            Uri.parse('http://127.0.0.1:${server.port}/transcribe'),
          );
          final assertion = expectLater(
            sendCloudRequest(
              request,
              timeout: const Duration(milliseconds: 500),
            ),
            throwsA(isA<TimeoutException>()),
          );
          await received.future.timeout(const Duration(seconds: 3));
          await assertion;
        } finally {
          await server.close(force: true);
        }
      },
    );
  }

  test(
    'successful requests close their client after reading the body',
    () async {
      final client = TrackingClient(
        (_) async => http.Response('{"ok":true}', 200),
      );
      final result = await http.runWithClient(
        () => sendCloudRequest(
          http.Request('POST', Uri.parse('https://example.test/')),
        ),
        () => client,
      );
      expect(jsonDecode(result.body)['ok'], isTrue);
      expect(client.closed, isTrue);
    },
  );

  test('timed out requests close their client', () async {
    final pending = Completer<http.Response>();
    final client = TrackingClient((_) => pending.future);
    await expectLater(
      http.runWithClient(
        () => sendCloudRequest(
          http.Request('POST', Uri.parse('https://example.test/')),
          timeout: const Duration(milliseconds: 10),
        ),
        () => client,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.closed, isTrue);
    pending.complete(http.Response('{}', 200));
  });

  for (final groq in [true, false]) {
    test(
      '${groq ? 'Groq' : 'Cloudflare'} timeout becomes a recoverable network error',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spokenlog-cloud-test-',
        );
        final audio = await File(
          '${root.path}/audio.wav',
        ).writeAsBytes(fixtures.wav());
        final client = TrackingClient(
          (_) async => throw TimeoutException('stalled'),
        );
        try {
          await expectLater(
            http.runWithClient(
              () => groq
                  ? GroqTranscriptionService().transcribeRecording(
                      recording: fixtures.item([audio]),
                      apiKey: 'test-only',
                      model: 'whisper-large-v3-turbo',
                      language: TranscriptionLanguage.auto,
                    )
                  : CloudflareTranscriptionService().transcribeRecording(
                      recording: fixtures.item([audio]),
                      accountId: 'test-only',
                      apiToken: 'test-only',
                      language: TranscriptionLanguage.auto,
                    ),
              () => client,
            ),
            throwsA(
              isA<TranscriptionException>()
                  .having((e) => e.kind, 'kind', TranscriptionErrorKind.network)
                  .having((e) => e.canFallback, 'fallback allowed', isTrue)
                  .having(
                    (e) => e.provider,
                    'provider',
                    groq ? 'Groq' : 'Cloudflare',
                  ),
            ),
          );
          expect(client.closed, isTrue);
          expect(await audio.exists(), isTrue);
        } finally {
          await root.delete(recursive: true);
        }
      },
    );
  }
}
