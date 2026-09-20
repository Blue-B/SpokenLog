import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_item.dart';

void main() {
  test('sums chunk durations and uses custom title', () {
    final item = RecordingItem(
      id: 'recording_1',
      title: '회의',
      createdAt: DateTime(2026, 9, 19),
      chunks: [
        RecordingChunk(audioPath: 'a.m4a', durationMs: 1000),
        RecordingChunk(audioPath: 'b.m4a', durationMs: 2500),
      ],
      storagePath: 'recordings/recording_1',
    );

    expect(item.durationMs, 3500);
    expect(item.duration, const Duration(milliseconds: 3500));
    expect(item.displayTitle, '회의');
  });

  test('falls back to default title', () {
    final item = RecordingItem(
      id: 'recording_1',
      title: '   ',
      createdAt: DateTime(2026, 9, 19),
      chunks: [],
      storagePath: 'recordings/recording_1',
    );

    expect(item.displayTitle, '새 녹음');
  });
}
