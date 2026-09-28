import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_provider.dart';
import '../models/transcription_result.dart';
import 'local_wav_input.dart';
import 'moonshine_model_manager.dart';
import 'sherpa_runtime.dart';

class MoonshineTranscriptionService {
  MoonshineTranscriptionService(this._modelManager);

  final MoonshineModelManager _modelManager;

  Future<TranscriptionResult> transcribeRecording({
    required RecordingItem recording,
    required TranscriptionLanguage language,
  }) async {
    if (recording.chunks.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Local Moonshine',
        message: '전사할 녹음 파일이 없습니다.',
      );
    }

    final unsupported = recording.chunks
        .where((chunk) => !chunk.audioPath.toLowerCase().endsWith('.wav'))
        .toList();
    if (unsupported.isNotEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unsupportedFormat,
        provider: 'Local Moonshine',
        message:
            '로컬 Moonshine은 WAV 녹음만 지원합니다. '
            '가져온 M4A/MP3/MP4/WebM 파일은 지원되지 않으니 '
            '클라우드 전사를 사용해 주세요.',
      );
    }

    await ensureLocalWavInputs(
      audioPaths: recording.audioPaths,
      provider: 'Local Moonshine',
      containerHint: 'M4A/MP3/MP4/WebM 파일은 클라우드 전사를 사용해 주세요.',
    );

    if (!language.supportedByMoonshineKo) {
      final needsConfirmation =
          TranscriptionProvider.localMoonshine.needsKoreanConfirmation(language);
      throw TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Local Moonshine',
        message: needsConfirmation
            ? 'Moonshine Tiny KO는 자동 언어 감지를 지원하지 않습니다. '
                '한국어 음성이면 언어를 한국어로 지정해 주세요. '
                '다른 언어는 SenseVoice, 로컬 Whisper, Groq 또는 Cloudflare를 사용해 주세요.'
            : '현재 설치된 Moonshine Tiny KO는 한국어 전용입니다. '
                '${language.label}에는 Groq, Cloudflare, SenseVoice 또는 로컬 Whisper를 사용해 주세요.',
      );
    }

    if (!await _modelManager.isInstalled()) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.modelNotInstalled,
        provider: 'Local Moonshine',
        message:
            'Moonshine Tiny KO 모델이 설치되어 있지 않습니다. '
            '전사 설정에서 모델을 먼저 다운로드해 주세요.',
      );
    }

    final paths = await _modelManager.paths();
    final request = _MoonshineDecodeRequest(
      encoderPath: paths.encoder,
      mergedDecoderPath: paths.mergedDecoder,
      tokensPath: paths.tokens,
      audioPaths: recording.audioPaths,
      numThreads: Platform.numberOfProcessors.clamp(1, 4).toInt(),
    );

    try {
      final texts = await Isolate.run(
        () => _decodeMoonshineBatch(request),
      );

      final text =
          texts.where((value) => value.trim().isNotEmpty).join('\n\n').trim();

      if (text.isEmpty) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unknown,
          provider: 'Local Moonshine',
          message: 'Moonshine에서 전사 결과를 만들지 못했습니다.',
        );
      }

      return TranscriptionResult(
        text: text,
        segments: const [],
        durationSeconds:
            recording.durationMs > 0 ? recording.durationMs / 1000 : null,
      );
    } on TranscriptionException {
      rethrow;
    } catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.unknown,
        provider: 'Local Moonshine',
        message: 'Moonshine 로컬 전사 중 오류가 발생했습니다.',
        detail: e.toString(),
      );
    }
  }
}

class _MoonshineDecodeRequest {
  const _MoonshineDecodeRequest({
    required this.encoderPath,
    required this.mergedDecoderPath,
    required this.tokensPath,
    required this.audioPaths,
    required this.numThreads,
  });

  final String encoderPath;
  final String mergedDecoderPath;
  final String tokensPath;
  final List<String> audioPaths;
  final int numThreads;
}

List<String> _decodeMoonshineBatch(_MoonshineDecodeRequest request) {
  initializeSherpaRuntime();

  final moonshine = sherpa.OfflineMoonshineModelConfig(
    encoder: request.encoderPath,
    mergedDecoder: request.mergedDecoderPath,
  );
  final model = sherpa.OfflineModelConfig(
    moonshine: moonshine,
    tokens: request.tokensPath,
    debug: false,
    numThreads: request.numThreads,
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(model: model),
  );

  final texts = <String>[];

  try {
    for (final path in request.audioPaths) {
      final wave = sherpa.readWave(path);
      ensureDecodedWaveUsable(
        sampleCount: wave.samples.length,
        sampleRate: wave.sampleRate,
        provider: 'Local Moonshine',
      );
      final stream = recognizer.createStream();

      try {
        stream.acceptWaveform(
          samples: wave.samples,
          sampleRate: wave.sampleRate,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        texts.add(result.text.trim());
      } finally {
        stream.free();
      }
    }
  } finally {
    recognizer.free();
  }

  return texts;
}
