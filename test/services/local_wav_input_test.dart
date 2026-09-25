import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/local_wav_input.dart';

/// Builds a WAV header plus [actualDataBytes] bytes of fake PCM data.
Uint8List buildWav({
  int audioFormat = 1,
  int channels = 1,
  int sampleRate = 16000,
  int bitsPerSample = 16,
  int dataSize = 3200,
  int actualDataBytes = 3200,
  int? declaredByteRate,
  int? declaredBlockAlign,
  int? declaredFmtSize,
}) {
  final blockAlign = channels * bitsPerSample ~/ 8;
  final byteRate = sampleRate * blockAlign;
  final fmtSize = declaredFmtSize ?? 16;

  final header = <int>[];
  void ascii(String value) => header.addAll(value.codeUnits);
  void u32(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.little);
    header.addAll(bytes.buffer.asUint8List());
  }

  void u16(int value) {
    final bytes = ByteData(2)..setUint16(0, value, Endian.little);
    header.addAll(bytes.buffer.asUint8List());
  }

  ascii('RIFF');
  u32(0);
  ascii('WAVE');
  ascii('fmt ');
  u32(fmtSize);
  u16(audioFormat);
  u16(channels);
  u32(sampleRate);
  u32(declaredByteRate ?? byteRate);
  u16(declaredBlockAlign ?? blockAlign);
  u16(bitsPerSample);
  if (fmtSize > 16) header.addAll(List<int>.filled(fmtSize - 16, 0));
  ascii('data');
  u32(dataSize);
  header.addAll(List<int>.filled(actualDataBytes, 0));
  return Uint8List.fromList(header);
}

void main() {
  group('localWavProblemFromHeader', () {
    test('accepts a normal 16-bit PCM WAV', () {
      final bytes = buildWav();
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        isNull,
      );
    });

    test('accepts float32 (audio_format 3) audio', () {
      final bytes = buildWav(audioFormat: 3, bitsPerSample: 32);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        isNull,
      );
    });

    test('detects a non RIFF/WAVE file', () {
      final bytes = Uint8List.fromList(
        List<int>.filled(64, 0x20)..setAll(0, 'OggS'.codeUnits),
      );
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.notRiffWave,
      );
    });

    test('rejects WAVE_FORMAT_EXTENSIBLE (0xFFFE)', () {
      final bytes = buildWav(audioFormat: 0xFFFE);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.unsupportedFormat,
      );
    });

    test('rejects 24-bit samples', () {
      final bytes = buildWav(bitsPerSample: 24);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.unsupportedBitDepth,
      );
    });

    test('rejects an inconsistent byte rate', () {
      final bytes = buildWav(declaredByteRate: 44100);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.inconsistentHeader,
      );
    });

    test('rejects an inconsistent block align', () {
      final bytes = buildWav(declaredBlockAlign: 4);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.inconsistentHeader,
      );
    });

    test('rejects a truncated data chunk (interrupted recording)', () {
      final bytes = buildWav(dataSize: 32000, actualDataBytes: 3200);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.truncatedAudioData,
      );
    });

    test('rejects an empty data chunk', () {
      final bytes = buildWav(dataSize: 0, actualDataBytes: 0);
      expect(
        localWavProblemFromHeader(bytes, fileLength: bytes.length),
        LocalWavProblem.missingAudioData,
      );
    });

    test('rejects a too-short file', () {
      final bytes = buildWav().sublist(0, 20);
      expect(
        localWavProblemFromHeader(
          Uint8List.fromList(bytes),
          fileLength: bytes.length,
        ),
        LocalWavProblem.notRiffWave,
      );
    });
  });

  group('localWavProblem', () {
    test('returns unreadable for a missing path', () async {
      expect(
        await localWavProblem('/tmp/spokenlog-does-not-exist.wav'),
        LocalWavProblem.unreadable,
      );
    });
  });

  group('ensureLocalWavInputs', () {
    test('rejects non-WAV containers before touching the header', () async {
      await expectLater(
        ensureLocalWavInputs(
          audioPaths: const ['/tmp/imported.m4a'],
          provider: 'Local Whisper',
          containerHint: 'hint',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('WAV 녹음만 지원'),
          ),
        ),
      );
    });
  });

  group('ensureDecodedWaveUsable', () {
    test('throws when sherpa readWave produced no samples', () {
      expect(
        () => ensureDecodedWaveUsable(
          sampleCount: 0,
          sampleRate: 0,
          provider: 'Local Moonshine',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when the sample rate is zero even with samples', () {
      expect(
        () => ensureDecodedWaveUsable(
          sampleCount: 100,
          sampleRate: 0,
          provider: 'Local Moonshine',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('accepts a decoded wave', () {
      expect(
        () => ensureDecodedWaveUsable(
          sampleCount: 16000,
          sampleRate: 16000,
          provider: 'Local Moonshine',
        ),
        returnsNormally,
      );
    });
  });
}
