import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_result.dart';
import 'wav_upload_chunk_service.dart';

class CloudflareTranscriptionService {
  final WavUploadChunkService _chunker = WavUploadChunkService();
  static const _model = '@cf/openai/whisper-large-v3-turbo';

  Future<TranscriptionResult> transcribeRecording({
    required RecordingItem recording,
    required String accountId,
    required String apiToken,
    required TranscriptionLanguage language,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (recording.chunks.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Cloudflare',
        message: '전사할 녹음 파일이 없습니다.',
      );
    }

    final prepared = await _chunker.prepare(recording);
    final allSegments = <TranscriptSegment>[];
    final texts = <String>[];
    var offsetSeconds = 0.0;

    try {
      for (var i = 0; i < prepared.files.length; i++) {
        final file = prepared.files[i];
        final result = await _transcribeOne(
          audioPath: file.path,
          accountId: accountId,
          apiToken: apiToken,
          language: language,
        );

        if (result.text.isNotEmpty) texts.add(result.text);
        allSegments.addAll(
          result.segments.map((segment) => segment.shifted(offsetSeconds)),
        );

        final duration = file.durationSeconds > 0
            ? file.durationSeconds
            : result.durationSeconds ?? 0;
        offsetSeconds += duration;
        onProgress?.call(i + 1, prepared.files.length);
      }
    } finally {
      await prepared.cleanup();
    }

    final text = texts.join('\n\n').trim();
    if (text.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unknown,
        provider: 'Cloudflare',
        message: 'Cloudflare 응답에 전사문이 없습니다.',
      );
    }

    return TranscriptionResult(
      text: text,
      segments: allSegments,
      durationSeconds: offsetSeconds > 0 ? offsetSeconds : null,
    );
  }

  Future<TranscriptionResult> _transcribeOne({
    required String audioPath,
    required String accountId,
    required String apiToken,
    required TranscriptionLanguage language,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Cloudflare',
        message: '녹음 파일을 찾을 수 없습니다.',
        detail: file.uri.pathSegments.last,
      );
    }

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/'
      '${accountId.trim()}/ai/run/$_model',
    );

    try {
      final bytes = await file.readAsBytes();
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiToken.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'audio': base64Encode(bytes),
          'task': 'transcribe',
          if (language.cloudCode != null) 'language': language.cloudCode,
          'vad_filter': true,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFromResponse(response);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unknown,
          provider: 'Cloudflare',
          message: 'Cloudflare 응답 형식이 예상과 다릅니다.',
        );
      }

      final root = Map<String, dynamic>.from(decoded);
      final rawResult = root['result'] is Map
          ? Map<String, dynamic>.from(root['result'] as Map)
          : root;

      final text = rawResult['text']?.toString().trim() ?? '';
      final rawSegments = rawResult['segments'];
      final segments = rawSegments is List
          ? rawSegments
              .whereType<Map>()
              .map(
                (value) => TranscriptSegment.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .where((segment) => segment.text.isNotEmpty)
              .toList()
          : <TranscriptSegment>[];

      double? duration;
      if (segments.isNotEmpty) {
        duration = segments
            .map((segment) => segment.endSeconds)
            .reduce((a, b) => a > b ? a : b);
      }

      return TranscriptionResult(
        text: text,
        segments: segments,
        durationSeconds: duration,
      );
    } on TranscriptionException {
      rethrow;
    } on SocketException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'Cloudflare',
        message: '인터넷 연결 문제로 Cloudflare에 접속하지 못했습니다.',
        detail: e.message,
      );
    } on http.ClientException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'Cloudflare',
        message: 'Cloudflare 요청 중 네트워크 오류가 발생했습니다.',
        detail: e.message,
      );
    }
  }

  TranscriptionException _errorFromResponse(http.Response response) {
    final detail = _extractErrorMessage(response.body);
    final status = response.statusCode;

    if (status == 401 || status == 403) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.authentication,
        provider: 'Cloudflare',
        statusCode: status,
        message:
            'Cloudflare 인증에 실패했습니다. Account ID와 API Token을 확인해 주세요.',
        detail: detail,
      );
    }

    if (status == 429) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.rateLimit,
        provider: 'Cloudflare',
        statusCode: status,
        retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? ''),
        message:
            'Cloudflare 무료 사용량, 요청 제한 또는 일시적인 처리 용량 제한에 도달했습니다.',
        detail: detail,
      );
    }

    if (status == 413) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.fileTooLarge,
        provider: 'Cloudflare',
        statusCode: status,
        message: 'Cloudflare에 보내는 녹음 조각의 크기가 너무 큽니다.',
        detail: detail,
      );
    }

    if (status >= 500) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.serviceUnavailable,
        provider: 'Cloudflare',
        statusCode: status,
        message: 'Cloudflare 서비스에 일시적인 문제가 발생했습니다.',
        detail: detail,
      );
    }

    return TranscriptionException(
      kind: TranscriptionErrorKind.invalidRequest,
      provider: 'Cloudflare',
      statusCode: status,
      message: 'Cloudflare 전사 요청을 처리하지 못했습니다.',
      detail: detail,
    );
  }

  String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          return (errors.first as Map)['message']?.toString();
        }
        return decoded['error']?.toString();
      }
    } catch (_) {}
    return body.trim().isEmpty ? null : body.trim();
  }
}
