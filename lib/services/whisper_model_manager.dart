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

/// Multilingual Whisper sizes offered from the sherpa-onnx int8 releases.
///
/// [tiny] keeps its original folder name so models installed by earlier
/// versions are still found.
enum WhisperModelSize {
  tiny('tiny', 12937772, 89855401),
  base('base', 29120534, 130672026),
  small('small', 112442483, 262226114);

  const WhisperModelSize(this.prefix, this.encoderBytes, this.decoderBytes);

  final String prefix;
  final int encoderBytes;
  final int decoderBytes;

  static const int tokensBytes = 816730;

  String get modelId => 'whisper-$prefix-multilingual-int8';
  String get repository => 'sherpa-onnx-whisper-$prefix';
  int get totalBytes => encoderBytes + decoderBytes + tokensBytes;

  /// Decimal megabytes, matching what the download servers report.
  int get downloadMegabytes => (totalBytes / 1000000).round();

  static WhisperModelSize fromModelId(String? id) {
    for (final size in values) {
      if (size.modelId == id) return size;
    }
    return WhisperModelSize.tiny;
  }
}

class WhisperModelManager {
  WhisperModelManager({this.size = WhisperModelSize.tiny});

  /// The size that [paths], [isInstalled], [download] and [deleteModel] act on.
  WhisperModelSize size;

  String get _baseUrl =>
      'https://huggingface.co/csukuangfj/${size.repository}/resolve/main';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}${size.modelId}',
    );
  }

  Future<WhisperModelPaths> paths() async {
    final dir = await _directory();
    final sep = Platform.pathSeparator;
    return WhisperModelPaths(
      encoder: '${dir.path}$sep${size.prefix}-encoder.int8.onnx',
      decoder: '${dir.path}$sep${size.prefix}-decoder.int8.onnx',
      tokens: '${dir.path}$sep${size.prefix}-tokens.txt',
    );
  }

  /// A file counts as complete when it is at least 90% of its published size,
  /// which rejects interrupted downloads without pinning exact byte counts.
  Future<bool> _isComplete(String path, int expectedBytes) async {
    final file = File(path);
    return await file.exists() && await file.length() >= expectedBytes * 0.9;
  }

  Future<bool> isInstalled() async {
    final p = await paths();
    return await _isComplete(p.encoder, size.encoderBytes) &&
        await _isComplete(p.decoder, size.decoderBytes) &&
        await _isComplete(p.tokens, WhisperModelSize.tokensBytes);
  }

  Future<void> download({
    void Function(double? progress, String label)? onProgress,
  }) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final p = await paths();
    final total = size.totalBytes;
    final encoderShare = size.encoderBytes / total;
    final decoderShare = size.decoderBytes / total;

    try {
      await _downloadFile(
        Uri.parse('$_baseUrl/${size.prefix}-encoder.int8.onnx?download=true'),
        File(p.encoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : progress * encoderShare,
            'Whisper 인코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/${size.prefix}-decoder.int8.onnx?download=true'),
        File(p.decoder),
        onProgress: (progress) {
          onProgress?.call(
            progress == null
                ? null
                : encoderShare + progress * decoderShare,
            'Whisper 디코더를 다운로드하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse('$_baseUrl/${size.prefix}-tokens.txt?download=true'),
        File(p.tokens),
        onProgress: (progress) {
          onProgress?.call(
            progress == null
                ? null
                : encoderShare +
                    decoderShare +
                    progress * (1 - encoderShare - decoderShare),
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
