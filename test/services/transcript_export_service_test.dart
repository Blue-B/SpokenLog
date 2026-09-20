import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_result.dart';
import 'package:voice_transcriber/services/transcript_export_service.dart';

void main() {
  final item = RecordingItem(
    id: 'sample',
    title: '회의 기록',
    createdAt: DateTime(2026, 9, 20),
    storagePath: '/tmp/sample',
    chunks: const [],
    transcript: '안녕하세요\n반갑습니다',
    segments: const [
      TranscriptSegment(
        startSeconds: 1.2,
        endSeconds: 3.4,
        text: '안녕하세요',
        speaker: 0,
      ),
      TranscriptSegment(
        startSeconds: 4,
        endSeconds: 6.25,
        text: '반갑습니다',
        speaker: 1,
      ),
    ],
  );

  test('builds speaker-aware txt', () {
    final text = TranscriptExportService().buildText(
      item,
      TranscriptExportFormat.txt,
    );

    expect(text, contains('[00:01] 화자 1: 안녕하세요'));
    expect(text, contains('[00:04] 화자 2: 반갑습니다'));
  });

  test('builds valid srt timing', () {
    final text = TranscriptExportService().buildText(
      item,
      TranscriptExportFormat.srt,
    );

    expect(text, contains('00:00:01,200 --> 00:00:03,400'));
    expect(text, contains('화자 1: 안녕하세요'));
  });

  test('builds webvtt header', () {
    final text = TranscriptExportService().buildText(
      item,
      TranscriptExportFormat.vtt,
    );

    expect(text, startsWith('WEBVTT'));
    expect(text, contains('00:00:04.000 --> 00:00:06.250'));
  });

  test('builds structured json', () {
    final text = TranscriptExportService().buildText(
      item,
      TranscriptExportFormat.json,
    );

    expect(text, contains('"title": "회의 기록"'));
    expect(text, contains('"speaker": 0'));
  });
}
