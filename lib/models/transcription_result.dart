class TranscriptSegment {
  const TranscriptSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    this.speaker,
  });

  final double startSeconds;
  final double endSeconds;
  final String text;
  final int? speaker;

  Map<String, dynamic> toJson() => {
        'start': startSeconds,
        'end': endSeconds,
        'text': text,
        'speaker': speaker,
      };

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      startSeconds: (json['start'] as num?)?.toDouble() ?? 0,
      endSeconds: (json['end'] as num?)?.toDouble() ?? 0,
      text: json['text']?.toString().trim() ?? '',
      speaker: (json['speaker'] as num?)?.toInt(),
    );
  }

  TranscriptSegment shifted(double offsetSeconds) {
    return TranscriptSegment(
      startSeconds: startSeconds + offsetSeconds,
      endSeconds: endSeconds + offsetSeconds,
      text: text,
      speaker: speaker,
    );
  }

  TranscriptSegment withSpeaker(int? value) {
    return TranscriptSegment(
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      text: text,
      speaker: value,
    );
  }

  TranscriptSegment withText(String value) {
    return TranscriptSegment(
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      text: value.trim(),
      speaker: speaker,
    );
  }
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.segments,
    this.durationSeconds,
    this.speakerLabels = const <int, String>{},
  });

  final String text;
  final List<TranscriptSegment> segments;
  final double? durationSeconds;
  final Map<int, String> speakerLabels;

  Map<String, dynamic> toJson() => {
        'text': text,
        'duration': durationSeconds,
        'speakerLabels': speakerLabels.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    final rawSegments = json['segments'];
    final rawSpeakerLabels = json['speakerLabels'];
    final speakerLabels = <int, String>{};
    if (rawSpeakerLabels is Map) {
      for (final entry in rawSpeakerLabels.entries) {
        final speaker = int.tryParse(entry.key.toString());
        final label = entry.value?.toString().trim() ?? '';
        if (speaker != null && speaker >= 0 && label.isNotEmpty) {
          speakerLabels[speaker] = label;
        }
      }
    }

    return TranscriptionResult(
      text: json['text']?.toString().trim() ?? '',
      durationSeconds: (json['duration'] as num?)?.toDouble(),
      speakerLabels: speakerLabels,
      segments: rawSegments is List
          ? rawSegments
              .whereType<Map>()
              .map(
                (segment) => TranscriptSegment.fromJson(
                  Map<String, dynamic>.from(segment),
                ),
              )
              .where((segment) => segment.text.isNotEmpty)
              .toList()
          : const [],
    );
  }

  TranscriptionResult withSegments(List<TranscriptSegment> value) {
    return TranscriptionResult(
      text: text,
      segments: value,
      durationSeconds: durationSeconds,
      speakerLabels: speakerLabels,
    );
  }

  TranscriptionResult withSpeakerLabels(Map<int, String> value) {
    return TranscriptionResult(
      text: text,
      segments: segments,
      durationSeconds: durationSeconds,
      speakerLabels: value,
    );
  }
}
