import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class WhisperModelPaths {
  const WhisperModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
  });

  final String encoder;
  final String decoder;
  final String tokens;
}

class WhisperModelManager {
  static const modelSizeBytes = 104 * 1024 * 1024;
  static const _baseUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-whisper-tiny/resolve/main';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}whisper-tiny-multilingual-int8',
    );
  }

  Future<WhisperModelPaths> paths() async {
    final dir = await _directory();
    return WhisperModelPaths(
      encoder: '${dir.path}${Platform.pathSeparator}tiny-encoder.int8.onnx',
      decoder: '${dir.path}${Platform.pathSeparator}tiny-decoder.int8.onnx',
      tokens: '${dir.path}${Platform.pathSeparator}tiny-tokens.txt',
    );
  }

  Future<bool> isInstalled() async {
    final p = await paths();
    final encoder = File(p.encoder);
    final decoder = File(p.decoder);
    final tokens = File(p.tokens);

    if (!await encoder.exists() ||
        !await decoder.exists() ||
        !await tokens.exists()) {
      return false;
    }

    return await encoder.length() > 10 * 1024 * 1024 &&
        await decoder.length() > 80 * 1024 * 1024 &&
        await tokens.length() > 100 * 1024;
  }

  Future<void> download({
    void Function(double? progress, String label)? onProgress,
  }) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final p = await paths();

    try {
      await _downloadFile(
        Uri.parse('$_baseUrl/tiny-encoder.int8.onnx?download=true'),
        File(p.encoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : progress * 0.13,
            'Whisper 인코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/tiny-decoder.int8.onnx?download=true'),
        File(p.decoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.13 + progress * 0.86,
            'Whisper 디코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/tiny-tokens.txt?download=true'),
        File(p.tokens),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.99 + progress * 0.01,
            'Whisper 토큰 파일을 준비하고 있습니다.',
          );
        },
      );

      if (!await isInstalled()) {
        throw Exception('다운로드한 Whisper 모델 파일이 올바르지 않습니다.');
      }

      onProgress?.call(1, 'Whisper 모델 설치가 완료되었습니다.');
    } catch (_) {
      await _deletePartFiles(dir);
      rethrow;
    }
  }

  Future<void> _downloadFile(
    Uri uri,
    File target, {
    required void Function(double? progress) onProgress,
  }) async {
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    final client = http.Client();
    IOSink? sink;

    try {
      final response = await client.send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Whisper 모델 다운로드에 실패했습니다 '
          '(HTTP ${response.statusCode}).',
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = part.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          total != null && total > 0 ? received / total : null,
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      await sink?.close();
      client.close();
    }
  }

  Future<void> _deletePartFiles(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.part')) {
        await entity.delete();
      }
    }
  }

  Future<void> deleteModel() async {
    final dir = await _directory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
