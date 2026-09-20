import 'dart:io';

import 'transcription_result.dart';

class RecordingChunk {
  const RecordingChunk({
    required this.audioPath,
    required this.durationMs,
  });

  final String audioPath;
  final int durationMs;

  String get fileName => File(audioPath).uri.pathSegments.last;
  Duration get duration => Duration(milliseconds: durationMs);
}

class RecordingItem {
  const RecordingItem({
    required this.id,
    required this.createdAt,
    required this.chunks,
    required this.storagePath,
    this.title,
    this.transcript,
    this.segments = const [],
    this.speakerLabels = const <int, String>{},
    this.collectionId,
    this.isFavorite = false,
    this.deletedAt,
    this.isLegacy = false,
  });

  final String id;
  final DateTime createdAt;
  final List<RecordingChunk> chunks;
  final String storagePath;
  final String? title;
  final String? transcript;
  final List<TranscriptSegment> segments;
  final Map<int, String> speakerLabels;
  final String? collectionId;
  final bool isFavorite;
  final DateTime? deletedAt;
  final bool isLegacy;

  String get fileName =>
      isLegacy && chunks.isNotEmpty ? chunks.first.fileName : id;

  String get displayTitle {
    final value = title?.trim();
    if (value != null && value.isNotEmpty) return value;
    return '새 녹음';
  }

  bool get hasTranscript => transcript?.trim().isNotEmpty == true;

  bool get isDeleted => deletedAt != null;

  String speakerLabel(int speaker) {
    final custom = speakerLabels[speaker]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return '화자 ${speaker + 1}';
  }

  int get durationMs =>
      chunks.fold(0, (sum, chunk) => sum + chunk.durationMs);

  Duration get duration => Duration(milliseconds: durationMs);

  List<String> get audioPaths =>
      chunks.map((chunk) => chunk.audioPath).toList();

  String get transcriptPath => isLegacy
      ? '${chunks.first.audioPath}.txt'
      : '$storagePath${Platform.pathSeparator}transcript.txt';

  String get transcriptJsonPath => isLegacy
      ? '${chunks.first.audioPath}.transcript.json'
      : '$storagePath${Platform.pathSeparator}transcript.json';

  String get metadataPath => isLegacy
      ? '${chunks.first.audioPath}.meta.json'
      : '$storagePath${Platform.pathSeparator}session.json';

  RecordingItem copyWith({
    String? title,
    String? transcript,
    List<TranscriptSegment>? segments,
    Map<int, String>? speakerLabels,
    String? collectionId,
    bool? isFavorite,
    DateTime? deletedAt,
  }) {
    return RecordingItem(
      id: id,
      createdAt: createdAt,
      chunks: chunks,
      storagePath: storagePath,
      title: title ?? this.title,
      transcript: transcript ?? this.transcript,
      segments: segments ?? this.segments,
      speakerLabels: speakerLabels ?? this.speakerLabels,
      collectionId: collectionId ?? this.collectionId,
      isFavorite: isFavorite ?? this.isFavorite,
      deletedAt: deletedAt ?? this.deletedAt,
      isLegacy: isLegacy,
    );
  }
}
