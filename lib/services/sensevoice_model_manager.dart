import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../utils/resumable_download.dart';

class SenseVoiceModelPaths {
  const SenseVoiceModelPaths({required this.model, required this.tokens});

  final String model;
  final String tokens;
}

class SenseVoiceModelManager {
  static const modelSizeBytes = 239 * 1024 * 1024;
  static const _baseUrl =
      'https://huggingface.co/csukuangfj/'
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}models'
      '${Platform.pathSeparator}sensevoice-small-int8',
    );
  }

  Future<SenseVoiceModelPaths> paths() async {
    final dir = await _directory();
    return SenseVoiceModelPaths(
      model: '${dir.path}${Platform.pathSeparator}model.int8.onnx',
      tokens: '${dir.path}${Platform.pathSeparator}tokens.txt',
    );
  }

  Future<bool> isInstalled() async {
    final p = await paths();
    final model = File(p.model);
    final tokens = File(p.tokens);

    if (!await model.exists() || !await tokens.exists()) return false;

    final modelLength = await model.length();
    final tokensLength = await tokens.length();
    return modelLength > 200 * 1024 * 1024 && tokensLength > 100 * 1024;
  }

  Future<int> installedSizeBytes() async {
    if (!await isInstalled()) return 0;
    final p = await paths();
    return await File(p.model).length() + await File(p.tokens).length();
  }

  Future<void> download({
    void Function(double? progress, String label)? onProgress,
  }) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final p = await paths();

    try {
      await downloadWithResume(
        Uri.parse('$_baseUrl/model.int8.onnx?download=true'),
        File(p.model),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : progress * 0.99,
            'SenseVoice 모델을 다운로드하고 있습니다.',
          );
        },
      );

      await downloadWithResume(
        Uri.parse('$_baseUrl/tokens.txt?download=true'),
        File(p.tokens),
        onProgress: (progress) {
          onProgress?.call(
            progress == null ? null : 0.99 + progress * 0.01,
            '토큰 파일을 준비하고 있습니다.',
          );
        },
      );

      if (!await isInstalled()) {
        throw Exception('다운로드한 로컬 모델 파일이 올바르지 않습니다.');
      }
      onProgress?.call(1, '로컬 모델 설치가 완료되었습니다.');
    } catch (_) {
      await _deletePartFiles(dir);
      rethrow;
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
