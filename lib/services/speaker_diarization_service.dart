import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_result.dart';
import 'speaker_diarization_model_manager.dart';
import 'sherpa_runtime.dart';

class SpeakerTurn {
  const SpeakerTurn({
    required this.startSeconds,
    required this.endSeconds,
    required this.speaker,
  });

  final double startSeconds;
  final double endSeconds;
  final int speaker;
}

class SpeakerDiarizationService {
  SpeakerDiarizationService(this._modelManager);

  final SpeakerDiarizationModelManager _modelManager;

  Future<List<SpeakerTurn>> diarizeRecording({
    required RecordingItem recording,
    required int numSpeakers,
    void Function(double progress)? onProgress,
  }) async {
    if (!await _modelManager.isInstalled()) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.modelNotInstalled,
        provider: 'Speaker diarization',
        message:
            '화자 구분 모델이 설치되어 있지 않습니다. '
            '전사 설정에서 모델을 먼저 다운로드해 주세요.',
      );
    }

    final unsupported = recording.audioPaths
        .where((path) => !path.toLowerCase().endsWith('.wav'))
        .toList();
    if (unsupported.isNotEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unsupportedFormat,
        provider: 'Speaker diarization',
        message: '로컬 화자 구분은 현재 WAV 녹음에서 지원됩니다.',
      );
    }

    final paths = await _modelManager.paths();
    final allTurns = <SpeakerTurn>[];
    var offsetSeconds = 0.0;

    for (var i = 0; i < recording.audioPaths.length; i++) {
      final audioPath = recording.audioPaths[i];
      final request = _DiarizationRequest(
        segmentationPath: paths.segmentation,
        embeddingPath: paths.embedding,
        audioPath: audioPath,
        numSpeakers: numSpeakers,
      );

      final decoded = await Isolate.run(
        () => _runDiarization(request),
      );

      final rawTurns = decoded['turns'];
      if (rawTurns is List) {
        for (final raw in rawTurns.whereType<Map>()) {
          allTurns.add(
            SpeakerTurn(
              startSeconds:
                  ((raw['start'] as num?)?.toDouble() ?? 0) + offsetSeconds,
              endSeconds:
                  ((raw['end'] as num?)?.toDouble() ?? 0) + offsetSeconds,
              speaker: (raw['speaker'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }

      final duration = (decoded['duration'] as num?)?.toDouble() ?? 0;
      offsetSeconds += duration;
      onProgress?.call((i + 1) / recording.audioPaths.length);
    }

    return allTurns;
  }

  TranscriptionResult attachSpeakers({
    required TranscriptionResult transcription,
    required List<SpeakerTurn> turns,
  }) {
    if (transcription.segments.isEmpty || turns.isEmpty) {
      return transcription;
    }

    final assigned = transcription.segments.map((segment) {
      SpeakerTurn? best;
      var bestOverlap = 0.0;

      for (final turn in turns) {
        final start = segment.startSeconds > turn.startSeconds
            ? segment.startSeconds
            : turn.startSeconds;
        final end = segment.endSeconds < turn.endSeconds
            ? segment.endSeconds
            : turn.endSeconds;
        final overlap = end > start ? end - start : 0.0;

        if (overlap > bestOverlap) {
          bestOverlap = overlap;
          best = turn;
        }
      }

      return segment.withSpeaker(bestOverlap > 0 ? best?.speaker : null);
    }).toList();

    return transcription.withSegments(assigned);
  }
}

class _DiarizationRequest {
  const _DiarizationRequest({
    required this.segmentationPath,
    required this.embeddingPath,
    required this.audioPath,
    required this.numSpeakers,
  });

  final String segmentationPath;
  final String embeddingPath;
  final String audioPath;
  final int numSpeakers;
}

Map<String, dynamic> _runDiarization(_DiarizationRequest request) {
  initializeSherpaRuntime();

  final segmentation = sherpa.OfflineSpeakerSegmentationModelConfig(
    pyannote: sherpa.OfflineSpeakerSegmentationPyannoteModelConfig(
      model: request.segmentationPath,
      windowShiftRatio: 0.1,
    ),
  );

  final embedding = sherpa.SpeakerEmbeddingExtractorConfig(
    model: request.embeddingPath,
  );

  final clustering = sherpa.FastClusteringConfig(
    numClusters: request.numSpeakers > 0 ? request.numSpeakers : -1,
    threshold: 0.5,
  );

  final config = sherpa.OfflineSpeakerDiarizationConfig(
    segmentation: segmentation,
    embedding: embedding,
    clustering: clustering,
    minDurationOn: 0.3,
    minDurationOff: 0.5,
  );

  final diarizer = sherpa.OfflineSpeakerDiarization(config);
  final wave = sherpa.readWave(request.audioPath);

  if (diarizer.sampleRate != wave.sampleRate) {
    throw Exception(
      '화자 구분은 ${diarizer.sampleRate}Hz WAV가 필요합니다. '
      '현재 파일은 ${wave.sampleRate}Hz입니다.',
    );
  }

  final segments = diarizer.process(samples: wave.samples);
  final duration = wave.sampleRate > 0
      ? wave.samples.length / wave.sampleRate
      : 0.0;

  return {
    'duration': duration,
    'turns': segments
        .map(
          (segment) => {
            'start': segment.start,
            'end': segment.end,
            'speaker': segment.speaker,
          },
        )
        .toList(),
  };
}
