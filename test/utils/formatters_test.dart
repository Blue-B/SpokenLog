import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/utils/formatters.dart';

void main() {
  group('formatDuration', () {
    test('formats minutes and seconds', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 7)), '02:07');
    });

    test('formats hours', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('clamps negative values', () {
      expect(formatDuration(const Duration(seconds: -1)), '00:00');
    });
  });

  group('formatTimestamp', () {
    test('formats segment timestamps', () {
      expect(formatTimestamp(65.9), '01:05');
      expect(formatTimestamp(3661.2), '01:01:01');
    });
  });

  group('formatFileSize', () {
    test('formats common sizes', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(2 * 1024 * 1024), '2.0 MB');
    });
  });
}
