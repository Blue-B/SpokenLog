import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MoonshineModelPaths {
  const MoonshineModelPaths({
    required this.encoder,
    required this.mergedDecoder,
    required this.tokens,
    required this.license,
  });

  final String encoder;
  final String mergedDecoder;
  final String tokens;
  final String license;
}

class MoonshineModelManager {
  static const modelSizeBytes = 69 * 1024 * 1024;
  static const _baseUrl =
      'https://huggingface.co/csukuangfj2/'
      'sherpa-onnx-moonshine-tiny-ko-quantized-2026-02-27/resolve/main';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}moonshine-tiny-ko',
    );
  }

  Future<MoonshineModelPaths> paths() async {
    final dir = await _directory();
    return MoonshineModelPaths(
      encoder: '${dir.path}${Platform.pathSeparator}encoder_model.ort',
      mergedDecoder:
          '${dir.path}${Platform.pathSeparator}decoder_model_merged.ort',
      tokens: '${dir.path}${Platform.pathSeparator}tokens.txt',
      license: '${dir.path}${Platform.pathSeparator}LICENSE',
    );
  }

  Future<bool> isInstalled() async {
    final p = await paths();
    final encoder = File(p.encoder);
    final decoder = File(p.mergedDecoder);
    final tokens = File(p.tokens);

    if (!await encoder.exists() ||
        !await decoder.exists() ||
        !await tokens.exists()) {
      return false;
    }

    return await encoder.length() > 10 * 1024 * 1024 &&
        await decoder.length() > 50 * 1024 * 1024 &&
        await tokens.length() > 100 * 1024;
  }

  Future<int> installedSizeBytes() async {
    if (!await isInstalled()) return 0;
    final p = await paths();
    return await File(p.encoder).length() +
        await File(p.mergedDecoder).length() +
        await File(p.tokens).length();
  }

  Future<void> download({
    void Function(double? progress, String label)? onProgress,
  }) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final p = await paths();

    try {
      await _downloadFile(
        Uri.parse('$_baseUrl/encoder_model.ort?download=true'),
        File(p.encoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : progress * 0.19,
            'Moonshine 인코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/decoder_model_merged.ort?download=true'),
        File(p.mergedDecoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.19 + progress * 0.80,
            'Moonshine 디코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/tokens.txt?download=true'),
        File(p.tokens),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.99 + progress * 0.008,
            'Moonshine 토큰 파일을 준비하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/LICENSE?download=true'),
        File(p.license),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.998 + progress * 0.002,
            'Moonshine 라이선스를 저장하고 있습니다.',
          );
        },
      );

      if (!await isInstalled()) {
        throw Exception('다운로드한 Moonshine 모델 파일이 올바르지 않습니다.');
      }

      onProgress?.call(1, 'Moonshine 모델 설치가 완료되었습니다.');
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
      final request = http.Request('GET', uri);
      final response = await client.send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Moonshine 모델 다운로드에 실패했습니다 '
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
