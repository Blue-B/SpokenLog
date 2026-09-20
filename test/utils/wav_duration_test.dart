import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/utils/wav_duration.dart';

Uint8List _wavHeader({
  int byteRate = 32000,
  int dataSize = 32000,
}) {
  final bytes = Uint8List(44);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, byteRate, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  return bytes;
}

void main() {
  test('reads duration from a normal PCM WAV header', () {
    final header = _wavHeader(dataSize: 32000);

    expect(
      wavDurationMsFromHeader(header, fileLength: 44 + 32000),
      1000,
    );
  });

  test('uses available bytes when interrupted WAV has stale data size', () {
    final header = _wavHeader(dataSize: 0x7fffffff);

    expect(
      wavDurationMsFromHeader(header, fileLength: 44 + 16000),
      500,
    );
  });

  test('rejects invalid or incomplete WAV headers', () {
    expect(
      wavDurationMsFromHeader(Uint8List(44), fileLength: 44),
      0,
    );
    expect(
      wavDurationMsFromHeader(_wavHeader(), fileLength: 20),
      0,
    );
  });
}
