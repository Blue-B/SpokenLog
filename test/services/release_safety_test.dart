import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/services/cloudflare_transcription_service.dart';
import 'package:voice_transcriber/services/local_wav_input.dart';
import 'package:voice_transcriber/services/recording_service.dart';
import 'package:voice_transcriber/services/wav_upload_chunk_service.dart';

Uint8List wav({
  int seconds = 1,
  int rate = 16000,
  int channels = 1,
  int? declaredSize,
}) {
  final size = seconds * rate * channels * 2;
  final bytes = Uint8List(44 + size);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, 36 + (declaredSize ?? size), Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, declaredSize ?? size, Endian.little);
  return bytes;
}

RecordingItem item(List<File> files, {int durationMs = 0}) => RecordingItem(
  id: 'fixture',
  createdAt: DateTime(2026),
  storagePath: files.first.parent.path,
  chunks: files
      .map((f) => RecordingChunk(audioPath: f.path, durationMs: durationMs))
      .toList(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  late Directory root;
  late RecordingService service;
  var recording = false;
  var failMetadata = false;
  var starts = 0;
  String? audioPath;
  Completer<void>? permissionGate;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('spokenlog-release-test-');
    recording = false;
    failMetadata = false;
    starts = 0;
    audioPath = null;
    permissionGate = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(recordChannel, (call) async {
      switch (call.method) {
        case 'create':
          final id = (call.arguments as Map)['recorderId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('com.llfbandit.record/events/$id'),
            (_) async => null,
          );
          return null;
        case 'hasPermission':
          await permissionGate?.future;
          return true;
        case 'isRecording':
          return recording;
        case 'start':
          starts++;
          audioPath = (call.arguments as Map)['path'] as String;
          await File(audioPath!).writeAsBytes(wav());
          recording = true;
          if (failMetadata) {
            await Directory(
              '${File(audioPath!).parent.path}/session.json',
            ).create();
          }
          return null;
        case 'stop':
          recording = false;
          return audioPath;
        case 'dispose':
          recording = false;
          return null;
        default:
          return null;
      }
    });
    service = RecordingService();
  });
  tearDown(() async {
    await service.dispose();
    messenger.setMockMethodCallHandler(recordChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await root.delete(recursive: true);
  });

  test('high-rate stereo WAV parts stay within the upload limit', () async {
    final source = await File(
      '${root.path}/stereo.wav',
    ).writeAsBytes(wav(seconds: 180, rate: 48000, channels: 2));
    final prepared = await WavUploadChunkService().prepare(item([source]));
    try {
      expect(prepared.files.length, greaterThan(1));
      for (final part in prepared.files) {
        expect(
          await File(part.path).length(),
          lessThanOrEqualTo(WavUploadChunkService.maxUploadBytes),
        );
        expect(await localWavProblem(part.path), isNull);
      }
      expect(
        prepared.files.fold<double>(0, (n, f) => n + f.durationSeconds),
        closeTo(180, 0.001),
      );
    } finally {
      await prepared.cleanup();
    }
  });

  test(
    'Cloudflare offsets include trailing silence and unknown WAV duration',
    () async {
      final first = await File(
        '${root.path}/first.wav',
      ).writeAsBytes(wav(seconds: 10));
      final second = await File(
        '${root.path}/second.wav',
      ).writeAsBytes(wav(seconds: 10));
      var requests = 0;
      final result = await http.runWithClient(
        () => CloudflareTranscriptionService().transcribeRecording(
          recording: item([first, second]),
          accountId: 'test-only',
          apiToken: 'not-a-secret',
          language: TranscriptionLanguage.auto,
        ),
        () => MockClient((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'result': {
                'text': 'speech',
                'segments': [
                  {'text': 'speech', 'start': 1, 'end': 5},
                ],
              },
            }),
            200,
          );
        }),
      );
      expect(requests, 2);
      expect(result.segments.last.startSeconds, 11);
      expect(result.durationSeconds, 20);
    },
  );

  test('metadata failure after microphone start stops recording', () async {
    failMetadata = true;
    await expectLater(service.start(), throwsA(isA<FileSystemException>()));
    expect(recording, isFalse);
    expect(await File(audioPath!).exists(), isTrue);
  });

  test(
    'rapid sessions get different directories and preserve first audio',
    () async {
      final first = await service.start();
      final firstPath = audioPath!;
      await service.stop();
      final second = await service.start();
      await service.stop();
      expect(second, isNot(first));
      expect(await File(firstPath).exists(), isTrue);
      expect((await service.loadRecordings()).length, 2);
    },
  );

  test('concurrent start while permission is pending is rejected', () async {
    permissionGate = Completer<void>();
    final first = service.start();
    final second = service.start();
    final rejection = expectLater(second, throwsException);
    permissionGate!.complete();
    await first;
    await rejection;
    expect(starts, 1);
    await service.stop();
  });

  for (final declared in [0, 0x7fffffff]) {
    test(
      'interrupted WAV size $declared is repaired before recovery',
      () async {
        final dir = await Directory(
          '${root.path}/recordings/interrupted',
        ).create(recursive: true);
        final file = await File(
          '${dir.path}/recording.wav',
        ).writeAsBytes(wav(declaredSize: declared));
        await File('${dir.path}/session.json').writeAsString(
          jsonEncode({
            'id': 'interrupted',
            'state': 'recording',
            'chunks': [
              {'file': 'recording.wav', 'durationMs': 0},
            ],
          }),
        );
        expect(await localWavProblem(file.path), isNotNull);
        final recovered = (await service.loadRecordings()).single;
        expect(recovered.durationMs, 1000);
        expect(await localWavProblem(file.path), isNull);
      },
    );
  }

  test(
    'stop metadata failure clears active state and allows a new session',
    () async {
      await service.start();
      final metadata = File('${File(audioPath!).parent.path}/session.json');
      await metadata.delete();
      await Directory(metadata.path).create();
      await expectLater(service.stop(), throwsA(isA<FileSystemException>()));
      expect(recording, isFalse);
      await service.start();
      await service.stop();
      expect(starts, 2);
    },
  );

  test(
    'repair preserves the original and leaves unrelated malformed WAVs alone',
    () async {
      final original = wav(declaredSize: 0);
      final file = await File(
        '${root.path}/interrupted.wav',
      ).writeAsBytes(original);
      expect(await repairInterruptedWav(file), isTrue);
      expect(
        await File('${file.path}.recovery-original').readAsBytes(),
        original,
      );
      final invalid = await File(
        '${root.path}/invalid.wav',
      ).writeAsBytes(Uint8List(44));
      expect(await repairInterruptedWav(invalid), isFalse);
      expect(await invalid.readAsBytes(), Uint8List(44));
    },
  );

  test('failed split removes already-prepared temporary files', () async {
    final first = await File(
      '${root.path}/first.wav',
    ).writeAsBytes(wav(seconds: 800));
    final invalid = await File(
      '${root.path}/invalid.wav',
    ).writeAsBytes(Uint8List(WavUploadChunkService.maxUploadBytes + 1));
    await expectLater(
      WavUploadChunkService().prepare(item([first, invalid])),
      throwsException,
    );
    expect(await root.list().where((e) => e is Directory).toList(), isEmpty);
  });

  test('reload does not recover the currently active recording', () async {
    await service.start();
    final metadata = File('${File(audioPath!).parent.path}/session.json');
    await service.loadRecordings();
    expect(jsonDecode(await metadata.readAsString())['state'], 'recording');
    await service.stop();
  });
}
