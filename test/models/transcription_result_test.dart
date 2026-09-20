import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_result.dart';

void main() {
  test('parses and shifts transcript segments', () {
    final result = TranscriptionResult.fromJson({
      'text': '안녕하세요',
      'duration': 3.5,
      'segments': [
        {
          'start': 0.5,
          'end': 2.0,
          'text': ' 안녕하세요 ',
          'speaker': 1,
        },
      ],
    });

    expect(result.text, '안녕하세요');
    expect(result.durationSeconds, 3.5);
    expect(result.segments, hasLength(1));
    expect(result.segments.first.speaker, 1);

    final shifted = result.segments.first.shifted(10);
    expect(shifted.startSeconds, 10.5);
    expect(shifted.endSeconds, 12.0);
    expect(shifted.text, '안녕하세요');
    expect(shifted.speaker, 1);
  });

  test('can attach and persist a speaker label', () {
    const segment = TranscriptSegment(
      startSeconds: 1,
      endSeconds: 3,
      text: 'hello',
    );

    final labeled = segment.withSpeaker(2);
    expect(labeled.speaker, 2);

    final restored = TranscriptSegment.fromJson(labeled.toJson());
    expect(restored.speaker, 2);
    expect(restored.text, 'hello');
  });

  test('ignores empty segment text', () {
    final result = TranscriptionResult.fromJson({
      'text': '테스트',
      'segments': [
        {'start': 0, 'end': 1, 'text': '   '},
      ],
    });

    expect(result.segments, isEmpty);
  });
}
