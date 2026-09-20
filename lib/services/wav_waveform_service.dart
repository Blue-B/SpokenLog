import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class WavWaveformService {
  Future<List<double>> readPeaks(
    String path, {
    int bucketCount = 180,
  }) async {
    if (!path.toLowerCase().endsWith('.wav')) return const [];

    final file = File(path);
    if (!await file.exists()) return const [];

    final raf = await file.open(mode: FileMode.read);
    try {
      final info = await _readInfo(raf);
      if (info == null ||
          info.audioFormat != 1 ||
          info.bitsPerSample != 16 ||
          info.channels <= 0 ||
          info.dataSize <= 0) {
        return const [];
      }

      final frameSize = info.channels * 2;
      final frameCount = info.dataSize ~/ frameSize;
      if (frameCount <= 0) return const [];

      final buckets = bucketCount.clamp(32, 320);
      final framesPerBucket =
          (frameCount / buckets).ceil().clamp(1, 1 << 30);
      final peaks = <double>[];

      for (var bucket = 0; bucket < buckets; bucket++) {
        final startFrame = bucket * framesPerBucket;
        if (startFrame >= frameCount) break;

        final framesLeft = frameCount - startFrame;
        final framesToInspect =
            framesLeft < framesPerBucket ? framesLeft : framesPerBucket;

        final sampleFrames = framesToInspect.clamp(1, 768);
        final step = (framesToInspect / sampleFrames).ceil().clamp(1, 1 << 30);
        var peak = 0.0;

        for (var frame = 0;
            frame < framesToInspect;
            frame += step) {
          final offset = info.dataOffset + (startFrame + frame) * frameSize;
          await raf.setPosition(offset);
          final bytes = await raf.read(frameSize);
          if (bytes.length < 2) break;

          for (var channel = 0; channel < info.channels; channel++) {
            final sampleOffset = channel * 2;
            if (sampleOffset + 2 > bytes.length) break;
            final data = ByteData.sublistView(
              Uint8List.fromList(bytes),
              sampleOffset,
              sampleOffset + 2,
            );
            final value =
                data.getInt16(0, Endian.little).abs() / 32768.0;
            if (value > peak) peak = value;
          }
        }

        peaks.add(peak.clamp(0.03, 1.0));
      }

      return peaks;
    } finally {
      await raf.close();
    }
  }

  Future<_WavWaveformInfo?> _readInfo(RandomAccessFile raf) async {
    final length = await raf.length();
    if (length < 44) return null;

    await raf.setPosition(0);
    final riff = await raf.read(12);
    if (riff.length < 12 ||
        ascii.decode(riff.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(riff.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      return null;
    }

    int? audioFormat;
    int? channels;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;

    var offset = 12;
    while (offset + 8 <= length) {
      await raf.setPosition(offset);
      final header = await raf.read(8);
      if (header.length < 8) break;

      final id = ascii.decode(header.sublist(0, 4), allowInvalid: true);
      final bytes = Uint8List.fromList(header);
      final size = ByteData.sublistView(bytes, 4, 8)
          .getUint32(0, Endian.little);
      final payloadOffset = offset + 8;

      if (id == 'fmt ') {
        await raf.setPosition(payloadOffset);
        final fmt = await raf.read(size < 32 ? size : 32);
        if (fmt.length >= 16) {
          final data = ByteData.sublistView(Uint8List.fromList(fmt));
          audioFormat = data.getUint16(0, Endian.little);
          channels = data.getUint16(2, Endian.little);
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
        bitsPerSample == null ||
        dataOffset == null ||
        dataSize == null) {
      return null;
    }

    return _WavWaveformInfo(
      audioFormat: audioFormat,
      channels: channels,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }
}

class _WavWaveformInfo {
  const _WavWaveformInfo({
    required this.audioFormat,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });

  final int audioFormat;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;
}
