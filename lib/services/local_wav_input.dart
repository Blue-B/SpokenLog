import 'dart:io';
import 'dart:typed_data';

import '../models/transcription_error.dart';

/// Why a WAV file cannot be handed to a local sherpa-onnx engine.
///
/// sherpa-onnx's `ReadWaveImpl` refuses these files and returns zero samples
/// with a `0` sample rate. Passing that into `acceptWaveform` makes the native
/// decoder abort the whole process instead of raising a Dart error, so local
/// engines validate the header first.
enum LocalWavProblem {
  unreadable,
  notRiffWave,
  unsupportedFormat,
  unsupportedBitDepth,
  inconsistentHeader,
  truncatedAudioData,
  missingAudioData,
}

extension LocalWavProblemReason on LocalWavProblem {
  String get reason => switch (this) {
    LocalWavProblem.unreadable => '파일을 읽을 수 없음',
    LocalWavProblem.notRiffWave => 'RIFF/WAVE 헤더 없음',
    LocalWavProblem.unsupportedFormat => 'PCM 또는 float32 형식이 아님',
    LocalWavProblem.unsupportedBitDepth => '8/16/32-bit 샘플이 아님',
    LocalWavProblem.inconsistentHeader => '헤더의 byte rate/block align 불일치',
    LocalWavProblem.truncatedAudioData => '데이터 크기보다 파일이 짧음(중단된 녹음)',
    LocalWavProblem.missingAudioData => '오디오 데이터가 없음',
  };
}

const int _maxHeaderBytes = 65536;

/// Pure header inspection that mirrors the acceptance rules of sherpa-onnx's
/// `ReadWaveImpl` (v1.13.8).
///
/// Returns `null` when the header is acceptable, otherwise the concrete
/// problem. [fileLength] is the full on-disk length so truncated data chunks
/// can be detected.
LocalWavProblem? localWavProblemFromHeader(
  Uint8List bytes, {
  required int fileLength,
}) {
  if (fileLength < 44 || bytes.length < 12) return LocalWavProblem.notRiffWave;

  final isRiff =
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46;
  final isWave =
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;
  if (!isRiff || !isWave) return LocalWavProblem.notRiffWave;

  final data = ByteData.sublistView(bytes);
  var sawFmt = false;
  var offset = 12;

  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final payload = offset + 8;

    // sherpa-onnx expects `fmt ` to be the first chunk (a leading `JUNK`
    // chunk is skipped). Anything else first is rejected.
    if (!sawFmt && id != 'fmt ' && id != 'JUNK') {
      return LocalWavProblem.unsupportedFormat;
    }

    if (id == 'JUNK') {
      final next = payload + size;
      if (next <= offset) return LocalWavProblem.unsupportedFormat;
      offset = next;
      continue;
    }

    if (id == 'fmt ') {
      if (size != 16 && size != 18) return LocalWavProblem.unsupportedFormat;
      if (payload + 16 > bytes.length) {
        return LocalWavProblem.unsupportedFormat;
      }

      final audioFormat = data.getUint16(payload, Endian.little);
      final channels = data.getUint16(payload + 2, Endian.little);
      final sampleRate = data.getUint32(payload + 4, Endian.little);
      final byteRate = data.getUint32(payload + 8, Endian.little);
      final blockAlign = data.getUint16(payload + 12, Endian.little);
      final bitsPerSample = data.getUint16(payload + 14, Endian.little);

      // 1 = PCM, 3 = IEEE float. 0xfffe (WAVE_FORMAT_EXTENSIBLE) is rejected.
      if (audioFormat != 1 && audioFormat != 3) {
        return LocalWavProblem.unsupportedFormat;
      }
      if (channels <= 0) return LocalWavProblem.unsupportedFormat;
      if (sampleRate <= 0) return LocalWavProblem.unsupportedFormat;
      if (bitsPerSample != 8 && bitsPerSample != 16 && bitsPerSample != 32) {
        return LocalWavProblem.unsupportedBitDepth;
      }

      // sherpa-onnx rejects a header whose byte rate / block align do not
      // match the declared rate, channel count and bit depth.
      final expectedByteRate = sampleRate * channels * bitsPerSample ~/ 8;
      final expectedBlockAlign = channels * bitsPerSample ~/ 8;
      if (byteRate != expectedByteRate || blockAlign != expectedBlockAlign) {
        return LocalWavProblem.inconsistentHeader;
      }

      sawFmt = true;
    } else if (id == 'data') {
      if (!sawFmt) return LocalWavProblem.unsupportedFormat;
      final available = fileLength - payload;
      if (size <= 0 || available <= 0) {
        return LocalWavProblem.missingAudioData;
      }
      // sherpa-onnx reads exactly `size` bytes and returns zero samples when
      // the file is shorter, which then aborts the native decoder.
      if (size > available) return LocalWavProblem.truncatedAudioData;
      return null;
    }

    final paddedSize = size + (size.isOdd ? 1 : 0);
    final nextOffset = payload + paddedSize;
    if (nextOffset <= offset) return LocalWavProblem.unsupportedFormat;
    offset = nextOffset;
  }

  return LocalWavProblem.missingAudioData;
}

/// Reads at most 64 KiB of [path] and returns the compatibility problem, or
/// `null` when sherpa-onnx can decode the file.
Future<LocalWavProblem?> localWavProblem(String path) async {
  RandomAccessFile? handle;
  try {
    handle = await File(path).open();
    final length = await handle.length();
    if (length < 44) return LocalWavProblem.notRiffWave;

    final headerLength = length < _maxHeaderBytes ? length : _maxHeaderBytes;
    final bytes = Uint8List.fromList(await handle.read(headerLength));
    return localWavProblemFromHeader(bytes, fileLength: length);
  } catch (_) {
    return LocalWavProblem.unreadable;
  } finally {
    await handle?.close();
  }
}

/// Finalizes a stopped, app-created PCM WAV without guessing other formats.
/// Keeps the original before replacing it with a validated, repaired copy.
Future<bool> repairInterruptedWav(File file) async {
  final problem = await localWavProblem(file.path);
  if (problem == null) return true;
  if (problem != LocalWavProblem.missingAudioData &&
      problem != LocalWavProblem.truncatedAudioData)
    return false;

  final input = await file.open();
  late Uint8List header;
  late int length;
  try {
    length = await input.length();
    header = await input.read(length.clamp(0, _maxHeaderBytes));
  } finally {
    await input.close();
  }
  final data = ByteData.sublistView(header);
  var offset = 12;
  int? blockAlign;
  while (offset + 8 <= header.length) {
    final id = String.fromCharCodes(header.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final payload = offset + 8;
    if (id == 'fmt ') {
      if (payload + 16 > header.length ||
          data.getUint16(payload, Endian.little) != 1 ||
          data.getUint16(payload + 14, Endian.little) != 16)
        return false;
      blockAlign = data.getUint16(payload + 12, Endian.little);
    } else if (id == 'data') {
      if (blockAlign == null || blockAlign <= 0) return false;
      final audioBytes = (length - payload) ~/ blockAlign * blockAlign;
      if (audioBytes <= 0 || payload + audioBytes - 8 > 0xffffffff)
        return false;
      data.setUint32(offset + 4, audioBytes, Endian.little);
      data.setUint32(4, payload + audioBytes - 8, Endian.little);
      if (localWavProblemFromHeader(header, fileLength: payload + audioBytes) !=
          null)
        return false;

      final temp = await file.parent.createTemp('.wav-recovery-');
      try {
        final repaired = await file.copy('${temp.path}/audio.wav');
        final output = await repaired.open(mode: FileMode.append);
        try {
          await output.setPosition(0);
          await output.writeFrom(header, 0, payload);
          await output.truncate(payload + audioBytes);
          await output.flush();
        } finally {
          await output.close();
        }
        if (await localWavProblem(repaired.path) != null) return false;
        final backup = File('${file.path}.recovery-original');
        if (!await backup.exists()) await file.copy(backup.path);
        await repaired.rename(file.path);
        return true;
      } finally {
        await temp.delete(recursive: true);
      }
    }
    offset = payload + size + (size.isOdd ? 1 : 0);
  }
  return false;
}

/// Throws [TranscriptionException] when any path is not a WAV that the local
/// sherpa-onnx engines can decode.
///
/// Non-`.wav` extensions are always rejected because the local engines never
/// convert other containers. WAV files whose header sherpa-onnx would refuse
/// are rejected with [TranscriptionErrorKind.unsupportedFormat] instead of
/// aborting the native decoder.
Future<void> ensureLocalWavInputs({
  required Iterable<String> audioPaths,
  required String provider,
  required String containerHint,
}) async {
  for (final path in audioPaths) {
    if (!path.toLowerCase().endsWith('.wav')) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.unsupportedFormat,
        provider: provider,
        message: '로컬 전사는 WAV 녹음만 지원합니다. $containerHint',
      );
    }

    final problem = await localWavProblem(path);
    if (problem == null) continue;

    throw TranscriptionException(
      kind: TranscriptionErrorKind.unsupportedFormat,
      provider: provider,
      message:
          '${File(path).uri.pathSegments.last} 파일은 로컬 전사에서 읽을 수 없는 '
          'WAV입니다 (${problem.reason}). 16-bit PCM WAV로 변환해 주세요.',
    );
  }
}

/// Guards the value returned by `sherpa.readWave` inside the decode isolate.
///
/// A failed `readWave` yields zero samples with a `0` sample rate; feeding that
/// to `acceptWaveform` aborts the native process, so it is rejected here as a
/// normal Dart error.
void ensureDecodedWaveUsable({
  required int sampleCount,
  required int sampleRate,
  required String provider,
}) {
  if (sampleRate <= 0 || sampleCount <= 0) {
    throw TranscriptionException(
      kind: TranscriptionErrorKind.unsupportedFormat,
      provider: provider,
      message:
          '로컬 모델이 오디오를 읽지 못했습니다. '
          '16-bit PCM WAV인지 확인해 주세요.',
    );
  }
}
