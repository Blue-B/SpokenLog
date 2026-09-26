import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../utils/wav_duration.dart';

class PreparedAudioFile {
  const PreparedAudioFile({required this.path, required this.durationSeconds});

  final String path;
  final double durationSeconds;
}

class PreparedAudioBatch {
  PreparedAudioBatch({required this.files, this.temporaryDirectory});

  final List<PreparedAudioFile> files;
  final Directory? temporaryDirectory;

  Future<void> cleanup() async {
    final dir = temporaryDirectory;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

class WavUploadChunkService {
  static const int maxUploadBytes = 24 * 1024 * 1024;
  static const Duration targetChunkDuration = Duration(minutes: 10);

  Future<PreparedAudioBatch> prepare(RecordingItem recording) async {
    if (recording.chunks.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        message: '전사할 녹음 파일이 없습니다.',
      );
    }

    final needsTemp = <RecordingChunk>[];
    final direct = <PreparedAudioFile>[];

    for (final chunk in recording.chunks) {
      final file = File(chunk.audioPath);
      if (!await file.exists()) {
        throw TranscriptionException(
          kind: TranscriptionErrorKind.invalidRequest,
          message: '녹음 파일을 찾을 수 없습니다.',
          detail: file.path,
        );
      }

      final size = await file.length();
      final isWav = file.path.toLowerCase().endsWith('.wav');

      if (size <= maxUploadBytes) {
        direct.add(
          PreparedAudioFile(
            path: file.path,
            durationSeconds: isWav
                ? await readWavDurationMs(file) / 1000
                : chunk.durationMs / 1000,
          ),
        );
      } else if (isWav) {
        needsTemp.add(chunk);
      } else {
        throw TranscriptionException(
          kind: TranscriptionErrorKind.fileTooLarge,
          message:
              '기존 녹음 파일이 클라우드 업로드 한도를 초과했습니다. '
              '새 녹음은 전사할 때만 임시 WAV 조각으로 자동 처리됩니다.',
          detail: file.uri.pathSegments.last,
        );
      }
    }

    if (needsTemp.isEmpty) {
      return PreparedAudioBatch(files: direct);
    }

    final tempRoot = await getTemporaryDirectory();
    final tempDir = Directory(
      '${tempRoot.path}${Platform.pathSeparator}'
      'voice_transcriber_upload_${DateTime.now().microsecondsSinceEpoch}',
    );
    await tempDir.create(recursive: true);

    final output = <PreparedAudioFile>[];
    var directIndex = 0;
    var tempIndex = 0;

    try {
      for (final original in recording.chunks) {
        final file = File(original.audioPath);
        final size = await file.length();

        if (size <= maxUploadBytes) {
          output.add(direct[directIndex++]);
          continue;
        }

        final parts = await _splitWav(file, tempDir, startIndex: tempIndex);
        tempIndex += parts.length;
        output.addAll(parts);
      }

      return PreparedAudioBatch(files: output, temporaryDirectory: tempDir);
    } catch (_) {
      await tempDir.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<PreparedAudioFile>> _splitWav(
    File source,
    Directory targetDir, {
    required int startIndex,
  }) async {
    final info = await _readWavInfo(source);

    if (info.audioFormat != 1 || info.bitsPerSample != 16) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unsupportedFormat,
        message: '대용량 WAV의 임시 분할은 현재 PCM 16-bit WAV만 지원합니다.',
      );
    }

    final targetBytes = min(
      info.byteRate * targetChunkDuration.inSeconds,
      maxUploadBytes - 44,
    );
    final alignedTarget = (targetBytes ~/ info.blockAlign) * info.blockAlign;

    final input = await source.open(mode: FileMode.read);
    final parts = <PreparedAudioFile>[];

    try {
      var remaining = info.dataSize;
      var dataOffset = info.dataOffset;
      var partIndex = startIndex;

      while (remaining > 0) {
        final partDataSize = remaining > alignedTarget
            ? alignedTarget
            : remaining;
        final alignedSize = (partDataSize ~/ info.blockAlign) * info.blockAlign;
        if (alignedSize <= 0) break;

        final outputFile = File(
          '${targetDir.path}${Platform.pathSeparator}'
          'upload_${partIndex.toString().padLeft(3, '0')}.wav',
        );
        partIndex += 1;

        final output = outputFile.openWrite();
        output.add(
          _buildPcmHeader(
            channels: info.channels,
            sampleRate: info.sampleRate,
            bitsPerSample: info.bitsPerSample,
            dataSize: alignedSize,
          ),
        );

        await input.setPosition(dataOffset);
        var bytesLeft = alignedSize;
        const readSize = 1024 * 1024;

        while (bytesLeft > 0) {
          final amount = bytesLeft > readSize ? readSize : bytesLeft;
          final bytes = await input.read(amount);
          if (bytes.isEmpty) {
            await output.close();
            throw const TranscriptionException(
              kind: TranscriptionErrorKind.unsupportedFormat,
              message: 'WAV 오디오 데이터가 잘렸습니다.',
            );
          }
          output.add(bytes);
          bytesLeft -= bytes.length;
        }

        await output.flush();
        await output.close();

        parts.add(
          PreparedAudioFile(
            path: outputFile.path,
            durationSeconds: alignedSize / info.byteRate,
          ),
        );

        dataOffset += alignedSize;
        remaining -= alignedSize;
      }
    } finally {
      await input.close();
    }

    if (parts.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        message: 'WAV 파일을 임시 전사 조각으로 나누지 못했습니다.',
      );
    }

    return parts;
  }

  Future<_WavInfo> _readWavInfo(File file) async {
    final raf = await file.open(mode: FileMode.read);

    try {
      final length = await raf.length();
      if (length < 44) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unsupportedFormat,
          message: '올바른 WAV 파일이 아닙니다.',
        );
      }

      final riff = await raf.read(12);
      if (riff.length < 12 ||
          ascii.decode(riff.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
          ascii.decode(riff.sublist(8, 12), allowInvalid: true) != 'WAVE') {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unsupportedFormat,
          message: '지원하지 않는 WAV 형식입니다.',
        );
      }

      int? audioFormat;
      int? channels;
      int? sampleRate;
      int? byteRate;
      int? blockAlign;
      int? bitsPerSample;
      int? dataOffset;
      int? dataSize;

      var offset = 12;
      while (offset + 8 <= length) {
        await raf.setPosition(offset);
        final header = await raf.read(8);
        if (header.length < 8) break;

        final id = ascii.decode(header.sublist(0, 4), allowInvalid: true);
        final size = ByteData.sublistView(
          Uint8List.fromList(header),
          4,
          8,
        ).getUint32(0, Endian.little);

        final payloadOffset = offset + 8;

        if (id == 'fmt ') {
          await raf.setPosition(payloadOffset);
          final fmt = await raf.read(size < 40 ? size : 40);
          if (fmt.length >= 16) {
            final data = ByteData.sublistView(Uint8List.fromList(fmt));
            audioFormat = data.getUint16(0, Endian.little);
            channels = data.getUint16(2, Endian.little);
            sampleRate = data.getUint32(4, Endian.little);
            byteRate = data.getUint32(8, Endian.little);
            blockAlign = data.getUint16(12, Endian.little);
            bitsPerSample = data.getUint16(14, Endian.little);
          }
        } else if (id == 'data') {
          dataOffset = payloadOffset;
          dataSize = size;
          if (audioFormat != null) break;
        }

        offset = payloadOffset + size + (size.isOdd ? 1 : 0);
      }

      if (audioFormat == null ||
          channels == null ||
          sampleRate == null ||
          byteRate == null ||
          blockAlign == null ||
          bitsPerSample == null ||
          dataOffset == null ||
          dataSize == null ||
          channels <= 0 ||
          sampleRate <= 0 ||
          byteRate != sampleRate * blockAlign ||
          blockAlign != channels * bitsPerSample ~/ 8 ||
          byteRate <= 0 ||
          blockAlign <= 0 ||
          dataSize <= 0 ||
          dataSize > length - dataOffset) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unsupportedFormat,
          message: 'WAV 헤더를 읽지 못했습니다.',
        );
      }

      return _WavInfo(
        audioFormat: audioFormat,
        channels: channels,
        sampleRate: sampleRate,
        byteRate: byteRate,
        blockAlign: blockAlign,
        bitsPerSample: bitsPerSample,
        dataOffset: dataOffset,
        dataSize: dataSize,
      );
    } finally {
      await raf.close();
    }
  }

  Uint8List _buildPcmHeader({
    required int channels,
    required int sampleRate,
    required int bitsPerSample,
    required int dataSize,
  }) {
    final blockAlign = channels * bitsPerSample ~/ 8;
    final byteRate = sampleRate * blockAlign;
    final bytes = Uint8List(44);
    final data = ByteData.sublistView(bytes);

    bytes.setRange(0, 4, ascii.encode('RIFF'));
    data.setUint32(4, 36 + dataSize, Endian.little);
    bytes.setRange(8, 12, ascii.encode('WAVE'));
    bytes.setRange(12, 16, ascii.encode('fmt '));
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    bytes.setRange(36, 40, ascii.encode('data'));
    data.setUint32(40, dataSize, Endian.little);

    return bytes;
  }
}

class _WavInfo {
  const _WavInfo({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.blockAlign,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });

  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int blockAlign;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;
}
