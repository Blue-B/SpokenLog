import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/services/cloud_config.dart';
import 'package:voice_transcriber/services/spokenlog_cloud_service.dart';

/// 16 kHz mono PCM16 WAV of silence.
Uint8List wav(double seconds) {
  final data = (seconds * 32000).round();
  final bytes = ByteData(44 + data);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 16000, Endian.little);
  bytes.setUint32(28, 32000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  late Directory dir;
  late HttpServer server;
  final requests = <HttpRequest>[];
  var credit = 600;
  var status = 200;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cloud_test');
    requests.clear();
    credit = 600;
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final account = {
        'credit_seconds': credit,
        'ads_today': 1,
        'ads_daily_limit': 5,
        'ad_reward_seconds': 600,
      };
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('authorization') != 'Bearer tok') {
        request.response.statusCode = 401;
      } else if (request.uri.path == '/api/v1/account') {
        request.response.write(jsonEncode(account));
      } else if (status == 402) {
        request.response
          ..statusCode = 402
          ..write(jsonEncode({'error': 'no_credits', ...account}));
      } else {
        final seconds = (body.length - 44) / 32000;
        credit -= seconds.ceil();
        request.response.write(jsonEncode({
          'text': 'chunk ${requests.length}',
          'segments': [
            {'start': 1, 'end': 2, 'text': 'chunk ${requests.length}'},
          ],
          'duration': seconds,
          ...account,
          'credit_seconds': credit,
        }));
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  SpokenLogCloudService service() => SpokenLogCloudService(
        config: CloudConfig(
          serverUrl: 'http://127.0.0.1:${server.port}/api/',
          androidServerClientId: '',
          desktopClientId: '',
          desktopClientSecret: '',
          rewardedAdUnitId: '',
        ),
      );

  Future<RecordingItem> recording(List<double> chunkSeconds) async {
    final chunks = <RecordingChunk>[];
    for (var i = 0; i < chunkSeconds.length; i++) {
      final file = File('${dir.path}/c$i.wav')..writeAsBytesSync(wav(chunkSeconds[i]));
      chunks.add(RecordingChunk(audioPath: file.path, durationMs: (chunkSeconds[i] * 1000).round()));
    }
    return RecordingItem(id: 'r', createdAt: DateTime(2026), chunks: chunks, storagePath: dir.path);
  }

  test('sends each chunk, shifts timestamps and reports progress', () async {
    final progress = <String>[];
    final result = await service().transcribeRecording(
      recording: await recording([3, 2]),
      idToken: 'tok',
      language: TranscriptionLanguage.ko,
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    expect(result.text, 'chunk 1\n\nchunk 2');
    expect(result.segments.map((s) => s.startSeconds), [1, 4]);
    expect(progress, ['0/2', '1/2', '1/2', '2/2']);
    expect(requests.first.uri.queryParameters['language'], 'ko');
    expect(requests.first.headers.contentType?.mimeType, 'audio/wav');
  });

  test('turns 402 into CloudCreditsException with the account', () async {
    status = 402;
    await expectLater(
      service().transcribeRecording(
          recording: await recording([1]), idToken: 'tok', language: TranscriptionLanguage.auto),
      throwsA(isA<CloudCreditsException>()
          .having((e) => e.account.creditSeconds, 'credits', 600)
          .having((e) => e.account.canWatchAd, 'can watch ad', true)),
    );
  });

  test('reads the account and reports expired sign-in', () async {
    final account = await service().account('tok');
    expect(account.creditSeconds, 600);
    expect(account.adRewardSeconds, 600);
    await expectLater(service().account('old'), throwsA(anything));
  });
}
