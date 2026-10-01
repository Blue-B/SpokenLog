import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_result.dart';
import 'cloud_request.dart';
import 'wav_upload_chunk_service.dart';

class GroqQuotaSnapshot {
  const GroqQuotaSnapshot({
    this.limitRequests,
    this.remainingRequests,
    this.resetRequests,
  });

  final int? limitRequests;
  final int? remainingRequests;
  final String? resetRequests;
}

class GroqTranscriptionService {
  final WavUploadChunkService _chunker = WavUploadChunkService();
  static final Uri _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');
  static const int _practicalUploadLimit = 24 * 1024 * 1024;

  GroqQuotaSnapshot? lastQuota;

  Future<TranscriptionResult> transcribeRecording({
    required RecordingItem recording,
    required String apiKey,
    required String model,
    required TranscriptionLanguage language,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (recording.chunks.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Groq',
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
          apiKey: apiKey,
          model: model,
          language: language,
        );

        if (result.text.isNotEmpty) texts.add(result.text);
        allSegments.addAll(
          result.segments.map((segment) => segment.shifted(offsetSeconds)),
        );

        final measuredDuration = result.durationSeconds;
        final segmentDuration = result.segments.isEmpty
            ? 0.0
            : result.segments
                .map((segment) => segment.endSeconds)
                .reduce((a, b) => a > b ? a : b);

        offsetSeconds += measuredDuration != null && measuredDuration > 0
            ? measuredDuration
            : file.durationSeconds > 0
                ? file.durationSeconds
                : segmentDuration;

        onProgress?.call(i + 1, prepared.files.length);
      }
    } finally {
      await prepared.cleanup();
    }

    final text = texts.join('\n\n').trim();
    if (text.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unknown,
        provider: 'Groq',
        message: 'Groq 응답에 전사문이 없습니다.',
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
    required String apiKey,
    required String model,
    required TranscriptionLanguage language,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.invalidRequest,
        provider: 'Groq',
        message: '녹음 파일을 찾을 수 없습니다.',
        detail: file.uri.pathSegments.last,
      );
    }

    final size = await file.length();
    if (size > _practicalUploadLimit) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.fileTooLarge,
        provider: 'Groq',
        message:
            '${file.uri.pathSegments.last} 파일이 클라우드 업로드 한도를 초과했습니다.',
      );
    }

    try {
      final request = http.MultipartRequest('POST', _endpoint)
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..fields['model'] = model
        ..fields['response_format'] = 'verbose_json'
        ..fields['timestamp_granularities[]'] = 'segment'
        ..files.add(await http.MultipartFile.fromPath('file', audioPath));

      final languageCode = language.cloudCode;
      if (languageCode != null) {
        request.fields['language'] = languageCode;
      }

      final response = await sendCloudRequest(request);
      _captureQuota(response.headers);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorFromResponse(response);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unknown,
          provider: 'Groq',
          message: 'Groq 응답 형식이 예상과 다릅니다.',
        );
      }

      final result = TranscriptionResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (result.text.isEmpty) {
        throw const TranscriptionException(
          kind: TranscriptionErrorKind.unknown,
          provider: 'Groq',
          message: 'Groq 응답에 전사문이 없습니다.',
        );
      }
      return result;
    } on TranscriptionException {
      rethrow;
    } on TimeoutException {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'Groq',
        message: 'Groq 응답 시간이 초과되었습니다. 연결을 확인하고 다시 시도해 주세요.',
      );
    } on SocketException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'Groq',
        message: '인터넷 연결 문제로 Groq에 접속하지 못했습니다.',
        detail: e.message,
      );
    } on http.ClientException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'Groq',
        message: 'Groq 요청 중 네트워크 오류가 발생했습니다.',
        detail: e.message,
      );
    }
  }

  void _captureQuota(Map<String, String> headers) {
    lastQuota = GroqQuotaSnapshot(
      limitRequests:
          int.tryParse(headers['x-ratelimit-limit-requests'] ?? ''),
      remainingRequests:
          int.tryParse(headers['x-ratelimit-remaining-requests'] ?? ''),
      resetRequests: headers['x-ratelimit-reset-requests'],
    );
  }

  TranscriptionException _errorFromResponse(http.Response response) {
    final detail = _extractErrorMessage(response.body);
    final status = response.statusCode;

    if (status == 401 || status == 403) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.authentication,
        provider: 'Groq',
        statusCode: status,
        message:
            'Groq API 키 인증에 실패했습니다. 설정에서 API 키를 확인하거나 교체해 주세요.',
        detail: detail,
      );
    }

    if (status == 429) {
      final retryAfter =
          int.tryParse(response.headers['retry-after'] ?? '');
      final waitText = retryAfter != null
          ? ' 약 $retryAfter초 후 다시 시도할 수 있습니다.'
          : '';

      return TranscriptionException(
        kind: TranscriptionErrorKind.rateLimit,
        provider: 'Groq',
        statusCode: status,
        retryAfterSeconds: retryAfter,
        message:
            'Groq 무료 사용량 또는 요청 속도 제한에 도달했습니다.$waitText '
            '로컬 SenseVoice나 Cloudflare로 전환할 수 있습니다.',
        detail: detail,
      );
    }

    if (status == 413) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.fileTooLarge,
        provider: 'Groq',
        statusCode: status,
        message: 'Groq에 보내는 녹음 조각의 크기가 너무 큽니다.',
        detail: detail,
      );
    }

    if (status >= 500) {
      return TranscriptionException(
        kind: TranscriptionErrorKind.serviceUnavailable,
        provider: 'Groq',
        statusCode: status,
        message:
            'Groq 서비스에 일시적인 문제가 발생했습니다. 잠시 후 다시 시도하거나 다른 전사 방식을 사용해 주세요.',
        detail: detail,
      );
    }

    return TranscriptionException(
      kind: TranscriptionErrorKind.invalidRequest,
      provider: 'Groq',
      statusCode: status,
      message: 'Groq 전사 요청을 처리하지 못했습니다.',
      detail: detail,
    );
  }

  String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          return error['message']?.toString();
        }
        return error?.toString();
      }
    } catch (_) {}
    return body.trim().isEmpty ? null : body.trim();
  }
}
