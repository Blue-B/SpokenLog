import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SpeakerDiarizationModelPaths {
  const SpeakerDiarizationModelPaths({
    required this.segmentation,
    required this.embedding,
  });

  final String segmentation;
  final String embedding;
}

class SpeakerDiarizationModelManager {
  static const modelSizeBytes = 42 * 1024 * 1024;

  static const _segmentationUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-pyannote-segmentation-3-0/resolve/main/'
      'model.int8.onnx?download=true';

  static const _embeddingUrl =
      'https://huggingface.co/csukuangfj/'
      'speaker-embedding-models/resolve/main/'
      '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx'
      '?download=true';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}speaker-diarization',
    );
  }

  Future<SpeakerDiarizationModelPaths> paths() async {
    final dir = await _directory();
    return SpeakerDiarizationModelPaths(
      segmentation:
          '${dir.path}${Platform.pathSeparator}pyannote-segmentation.int8.onnx',
      embedding:
          '${dir.path}${Platform.pathSeparator}3dspeaker-embedding.onnx',
    );
  }

  Future<bool> isInstalled() async {
    final p = await paths();
    final segmentation = File(p.segmentation);
    final embedding = File(p.embedding);

    if (!await segmentation.exists() || !await embedding.exists()) {
      return false;
    }

    return await segmentation.length() > 1024 * 1024 &&
        await embedding.length() > 30 * 1024 * 1024;
  }

  Future<void> download({
    void Function(double? progress, String label)? onProgress,
  }) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final p = await paths();

    try {
      await _downloadFile(
        Uri.parse(_segmentationUrl),
        File(p.segmentation),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : progress * 0.05,
            '화자 구분 모델을 준비하고 있습니다.',
          );
        },
      );

      await _downloadFile(
        Uri.parse(_embeddingUrl),
        File(p.embedding),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.05 + progress * 0.95,
            '화자 음성 특징 모델을 다운로드하고 있습니다.',
          );
        },
      );

      if (!await isInstalled()) {
        throw Exception('다운로드한 화자 구분 모델이 올바르지 않습니다.');
      }

      onProgress?.call(1, '화자 구분 모델 설치가 완료되었습니다.');
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
          '화자 구분 모델 다운로드에 실패했습니다 '
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
