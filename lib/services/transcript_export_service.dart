import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../models/recording_item.dart';
import '../models/transcription_result.dart';

enum TranscriptExportFormat {
  txt,
  srt,
  vtt,
  json;

  String get extension => name.toLowerCase();

  String get label => switch (this) {
        TranscriptExportFormat.txt => 'TXT',
        TranscriptExportFormat.srt => 'SRT',
        TranscriptExportFormat.vtt => 'VTT',
        TranscriptExportFormat.json => 'JSON',
      };
}

class TranscriptExportService {
  String buildText(
    RecordingItem item,
    TranscriptExportFormat format,
  ) {
    return switch (format) {
      TranscriptExportFormat.txt => _txt(item),
      TranscriptExportFormat.srt => _srt(item),
      TranscriptExportFormat.vtt => _vtt(item),
      TranscriptExportFormat.json => _json(item),
    };
  }

  Future<bool> save(
    RecordingItem item,
    TranscriptExportFormat format,
  ) async {
    if (!item.hasTranscript) {
      throw StateError('내보낼 전사문이 없습니다.');
    }

    final content = buildText(item, format);
    final fileName = '${_safeFileName(item.displayTitle)}.${format.extension}';

    final result = await FilePicker.saveFile(
      dialogTitle: '전사문 내보내기',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [format.extension],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );

    return result != null;
  }

  String _txt(RecordingItem item) {
    if (item.segments.isEmpty) {
      return item.transcript?.trim() ?? '';
    }

    return item.segments
        .map(
          (segment) =>
              '[${_plainTime(segment.startSeconds)}] ${_speakerText(item, segment)}',
        )
        .join('\n');
  }

  String _srt(RecordingItem item) {
    final segments = _segmentsOrFallback(item);
    final buffer = StringBuffer();

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      buffer
        ..writeln(index + 1)
        ..writeln(
          '${_subtitleTime(segment.startSeconds, comma: true)} --> '
          '${_subtitleTime(_safeEnd(segment), comma: true)}',
        )
        ..writeln(_speakerText(item, segment))
        ..writeln();
    }

    return buffer.toString().trimRight();
  }

  String _vtt(RecordingItem item) {
    final segments = _segmentsOrFallback(item);
    final buffer = StringBuffer('WEBVTT\n\n');

    for (final segment in segments) {
      buffer
        ..writeln(
          '${_subtitleTime(segment.startSeconds)} --> '
          '${_subtitleTime(_safeEnd(segment))}',
        )
        ..writeln(_speakerText(segment))
        ..writeln();
    }

    return buffer.toString().trimRight();
  }

  String _json(RecordingItem item) {
    final payload = <String, dynamic>{
      'title': item.displayTitle,
      'createdAt': item.createdAt.toIso8601String(),
      'text': item.transcript?.trim() ?? '',
      'speakerLabels': item.speakerLabels.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'segments': item.segments.map((segment) => segment.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  List<TranscriptSegment> _segmentsOrFallback(RecordingItem item) {
    if (item.segments.isNotEmpty) return item.segments;

    final text = item.transcript?.trim() ?? '';
    if (text.isEmpty) return const [];

    final duration = item.durationMs > 0
        ? item.durationMs / 1000
        : 5.0;

    return [
      TranscriptSegment(
        startSeconds: 0,
        endSeconds: duration > 0 ? duration : 5,
        text: text,
      ),
    ];
  }

  double _safeEnd(TranscriptSegment segment) {
    if (segment.endSeconds > segment.startSeconds) {
      return segment.endSeconds;
    }
    return segment.startSeconds + 2;
  }

  String _speakerText(RecordingItem item, TranscriptSegment segment) {
    final speaker = segment.speaker;
    if (speaker == null) return segment.text;
    return '${item.speakerLabel(speaker)}: ${segment.text}';
  }

  String _plainTime(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  String _subtitleTime(double seconds, {bool comma = false}) {
    final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    final milliseconds = (safe * 1000).round();
    final hours = milliseconds ~/ 3600000;
    final minutes = (milliseconds % 3600000) ~/ 60000;
    final secs = (milliseconds % 60000) ~/ 1000;
    final millis = milliseconds % 1000;
    final separator = comma ? ',' : '.';

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}'
        '$separator${millis.toString().padLeft(3, '0')}';
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? 'transcript' : cleaned;
  }
}
