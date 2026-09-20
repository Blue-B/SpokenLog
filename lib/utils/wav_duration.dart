import 'dart:io';
import 'dart:typed_data';

const int _maxHeaderBytes = 65536;

Future<int> readWavDurationMs(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final fileLength = await handle.length();
    if (fileLength < 44) return 0;

    final headerLength =
        fileLength < _maxHeaderBytes ? fileLength : _maxHeaderBytes;
    final bytes = await handle.read(headerLength);
    return wavDurationMsFromHeader(
      Uint8List.fromList(bytes),
      fileLength: fileLength,
    );
  } catch (_) {
    return 0;
  } finally {
    await handle?.close();
  }
}

int wavDurationMsFromHeader(
  Uint8List bytes, {
  required int fileLength,
}) {
  if (bytes.length < 44 ||
      fileLength < 44 ||
      bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46 ||
      bytes[8] != 0x57 ||
      bytes[9] != 0x41 ||
      bytes[10] != 0x56 ||
      bytes[11] != 0x45) {
    return 0;
  }

  final data = ByteData.sublistView(bytes);
  int? byteRate;
  int? dataOffset;
  int? declaredDataSize;
  var offset = 12;

  while (offset + 8 <= bytes.length) {
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final payloadOffset = offset + 8;
    final isFmt = bytes[offset] == 0x66 &&
        bytes[offset + 1] == 0x6d &&
        bytes[offset + 2] == 0x74 &&
        bytes[offset + 3] == 0x20;
    final isData = bytes[offset] == 0x64 &&
        bytes[offset + 1] == 0x61 &&
        bytes[offset + 2] == 0x74 &&
        bytes[offset + 3] == 0x61;

    if (isFmt && chunkSize >= 16 && payloadOffset + 12 <= bytes.length) {
      byteRate = data.getUint32(payloadOffset + 8, Endian.little);
    }
    if (isData) {
      dataOffset = payloadOffset;
      declaredDataSize = chunkSize;
      break;
    }

    final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
    final nextOffset = payloadOffset + paddedSize;
    if (nextOffset <= offset) return 0;
    offset = nextOffset;
  }

  if (byteRate == null || byteRate <= 0 || dataOffset == null) return 0;
  final available = fileLength - dataOffset;
  if (available <= 0) return 0;

  final declared = declaredDataSize ?? 0;
  final audioBytes =
      declared > 0 && declared <= available ? declared : available;
  return audioBytes * 1000 ~/ byteRate;
}
