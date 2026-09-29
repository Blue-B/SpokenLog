import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/local_audio_windows.dart';

Float32List _tone(int seconds, int rate) =>
    Float32List(seconds * rate)..fillRange(0, seconds * rate, 0.5);

void main() {
  group('planAudioWindows', () {
    test('short audio stays one window', () {
      final samples = _tone(10, 16000);
      expect(
        planAudioWindows(samples, 16000, maxSeconds: 28),
        [(start: 0, end: samples.length)],
      );
    });

    test('empty audio or invalid rate gives no windows', () {
      expect(planAudioWindows(Float32List(0), 16000, maxSeconds: 28), isEmpty);
      expect(planAudioWindows(_tone(1, 16000), 0, maxSeconds: 28), isEmpty);
    });

    test('long audio is covered without gaps and never exceeds the limit', () {
      const rate = 16000;
      final samples = _tone(200, rate);
      final windows = planAudioWindows(samples, rate, maxSeconds: 28);

      expect(windows.first.start, 0);
      expect(windows.last.end, samples.length);
      for (var i = 0; i < windows.length; i++) {
        expect(windows[i].end - windows[i].start, lessThanOrEqualTo(28 * rate));
        expect(windows[i].end, greaterThan(windows[i].start));
        if (i > 0) expect(windows[i].start, windows[i - 1].end);
      }
      // 200 s in windows of at most 28 s needs at least 8 pieces.
      expect(windows.length, greaterThanOrEqualTo(8));
    });

    test('cuts at the quiet gap instead of mid-speech', () {
      const rate = 16000;
      final samples = _tone(70, rate);
      // Silence between 26.0 s and 26.4 s, inside the 4 s search area.
      samples.fillRange((26.0 * rate).round(), (26.4 * rate).round(), 0);

      final first = planAudioWindows(samples, rate, maxSeconds: 28).first;
      expect(first.end, inInclusiveRange((26.0 * rate).round(), (26.4 * rate).round()));
    });

    test('works at other sample rates', () {
      const rate = 8000;
      final samples = _tone(90, rate);
      final windows = planAudioWindows(samples, rate, maxSeconds: 30);
      expect(windows.last.end, samples.length);
      expect(windows.every((w) => w.end - w.start <= 30 * rate), isTrue);
    });
  });

  group('planSpeechWindows', () {
    const rate = 16000;

    // Alternating speech-like bursts and silences: (seconds, isSpeech).
    Float32List build(List<(double, bool)> parts) {
      final out = <double>[];
      for (final (seconds, speech) in parts) {
        final n = (seconds * rate).round();
        for (var i = 0; i < n; i++) {
          out.add(speech ? (i.isEven ? 0.3 : -0.3) : 0.0);
        }
      }
      return Float32List.fromList(out);
    }

    test('cuts at pauses and drops silence', () {
      final samples = build([
        (1.0, false),
        (2.0, true), (0.8, false), // first sentence
        (2.5, true), (1.5, false), // second sentence
        (3.5, true), (1.0, false), // third sentence
      ]);
      final windows = planSpeechWindows(samples, rate, minSeconds: 1.5);
      expect(windows.length, 3);
      // Every piece is roughly the spoken part plus a little padding.
      expect((windows[0].end - windows[0].start) / rate, closeTo(2.2, 0.2));
      expect((windows[1].end - windows[1].start) / rate, closeTo(2.7, 0.2));
      expect((windows[2].end - windows[2].start) / rate, closeTo(3.7, 0.2));
      // Nothing overlaps and nothing runs backwards.
      for (var i = 1; i < windows.length; i++) {
        expect(windows[i].start, greaterThanOrEqualTo(windows[i - 1].end));
      }
      // The leading second of silence is not included.
      expect(windows.first.start, greaterThan((0.8 * rate).round()));
    });

    test('merges short phrases until the minimum length', () {
      final samples = build([
        (1.0, true), (0.5, false),
        (1.0, true), (0.5, false),
        (1.0, true), (0.5, false),
        (4.0, true),
      ]);
      final windows = planSpeechWindows(samples, rate, minSeconds: 3);
      expect(windows.length, 2);
    });

    test('an unbroken stretch is cut so no piece exceeds the maximum', () {
      final samples = build([(40.0, true)]);
      final windows = planSpeechWindows(samples, rate, maxSeconds: 12);
      expect(windows.length, greaterThanOrEqualTo(4));
      expect(windows.every((w) => w.end - w.start <= 12 * rate), isTrue);
      expect(windows.last.end, samples.length);
    });

    test('pure silence falls back to transcribing everything', () {
      final samples = Float32List(20 * rate);
      final windows = planSpeechWindows(samples, rate);
      expect(windows, isNotEmpty);
      expect(windows.first.start, 0);
      expect(windows.last.end, samples.length);
    });

    test('empty audio gives no pieces', () {
      expect(planSpeechWindows(Float32List(0), rate), isEmpty);
    });
  });

  group('joinTranscriptPieces', () {
    test('joins spaced languages with one space and skips blanks', () {
      expect(
        joinTranscriptPieces(['Hello there.', '', '  How are you?  ']),
        'Hello there. How are you?',
      );
      expect(joinTranscriptPieces(['안녕하세요.', '반갑습니다.']), '안녕하세요. 반갑습니다.');
    });

    test('does not insert spaces around Chinese or Japanese text', () {
      expect(joinTranscriptPieces(['今天天气很好。', '我们出去玩。']), '今天天气很好。我们出去玩。');
      expect(joinTranscriptPieces(['こんにちは。', 'よろしく。']), 'こんにちは。よろしく。');
    });

    test('empty input gives an empty string', () {
      expect(joinTranscriptPieces(const []), '');
    });
  });
}
