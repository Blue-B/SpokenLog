import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/sensevoice_transcription_service.dart';

void main() {
  test('long Korean lines break between words, not inside one', () {
    // "기능이 완성되었고 안드로이드와": the 6-second limit falls on "고",
    // which continues the word "완성되었고".
    final tokens = ['▁기능', '이', '▁완성', '되', '었', '고', '▁안드로이드', '와'];
    final times = [0.0, 1.2, 2.4, 3.6, 4.8, 6.0, 7.2, 8.4];
    final segments = buildSenseVoiceSegments(
        tokens: tokens, timestamps: times, durationSeconds: 9);

    expect(segments.map((s) => s['text']), ['기능이 완성되었고', '안드로이드와']);
  });

  test('text without spaces still breaks after 10 seconds', () {
    final tokens = List.generate(12, (i) => '字');
    final times = List.generate(12, (i) => i.toDouble());
    final segments = buildSenseVoiceSegments(
        tokens: tokens, timestamps: times, durationSeconds: 12);

    expect(segments.length, 2);
    expect(segments.first['text'], '字' * 10);
  });
}
