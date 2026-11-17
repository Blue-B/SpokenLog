import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/recording_item.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_result.dart';
import 'cloud_config.dart';
import 'cloud_request.dart';
import 'wav_upload_chunk_service.dart';

/// Credits and ad allowance of the signed-in account.
class CloudAccount {
  const CloudAccount({
    required this.creditSeconds,
    required this.adsToday,
    required this.adsDailyLimit,
    required this.adRewardSeconds,
  });

  factory CloudAccount.fromJson(Map<String, dynamic> json) => CloudAccount(
        creditSeconds: (json['credit_seconds'] as num?)?.toInt() ?? 0,
        adsToday: (json['ads_today'] as num?)?.toInt() ?? 0,
        adsDailyLimit: (json['ads_daily_limit'] as num?)?.toInt() ?? 0,
        adRewardSeconds: (json['ad_reward_seconds'] as num?)?.toInt() ?? 0,
      );

  final int creditSeconds;
  final int adsToday;
  final int adsDailyLimit;
  final int adRewardSeconds;

  bool get canWatchAd => adsToday < adsDailyLimit;
}

/// The account has too little cloud time for the next chunk.
class CloudCreditsException extends TranscriptionException {
  const CloudCreditsException(this.account)
      : super(
          kind: TranscriptionErrorKind.rateLimit,
          provider: 'SpokenLog',
          message: 'SpokenLog 클라우드 시간이 부족합니다.',
        );

  final CloudAccount account;
}

/// Sends WAV chunks to the SpokenLog cloud server, which picks the backend.
class SpokenLogCloudService {
  SpokenLogCloudService({CloudConfig? config}) : _config = config ?? CloudConfig.current;

  final CloudConfig _config;
  final WavUploadChunkService _chunker = WavUploadChunkService();

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_config.serverUrl);
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
  }

  Future<CloudAccount> account(String idToken) async {
    final response = await sendCloudRequest(
      http.Request('GET', _uri('/v1/account'))
        ..headers['Authorization'] = 'Bearer $idToken',
    );
    if (response.statusCode != 200) throw _error(response);
    return CloudAccount.fromJson(_json(response));
  }

  Future<TranscriptionResult> transcribeRecording({
    required RecordingItem recording,
    required String idToken,
    required TranscriptionLanguage language,
    void Function(int completed, int total)? onProgress,
    void Function(CloudAccount account)? onAccount,
  }) async {
    final prepared = await _chunker.prepare(recording);
    final texts = <String>[];
    final segments = <TranscriptSegment>[];
    var offset = 0.0;
    try {
      for (var i = 0; i < prepared.files.length; i++) {
        onProgress?.call(i, prepared.files.length);
        final file = prepared.files[i];
        final request = http.Request(
          'POST',
          _uri('/v1/transcribe', {
            if (language.cloudCode != null) 'language': language.cloudCode!,
          }),
        )
          ..headers['Authorization'] = 'Bearer $idToken'
          ..headers['Content-Type'] = 'audio/wav'
          ..bodyBytes = await File(file.path).readAsBytes();
        final response = await _send(request);
        final body = _json(response);
        if (response.statusCode == 402) throw CloudCreditsException(CloudAccount.fromJson(body));
        if (response.statusCode != 200) throw _error(response);

        onAccount?.call(CloudAccount.fromJson(body));
        final text = (body['text'] as String? ?? '').trim();
        if (text.isNotEmpty) texts.add(text);
        for (final raw in (body['segments'] as List? ?? const []).whereType<Map>()) {
          final segment = TranscriptSegment.fromJson(Map<String, dynamic>.from(raw));
          if (segment.text.isNotEmpty) segments.add(segment.shifted(offset));
        }
        final duration = (body['duration'] as num?)?.toDouble() ?? file.durationSeconds;
        offset += duration > 0 ? duration : file.durationSeconds;
        onProgress?.call(i + 1, prepared.files.length);
      }
    } finally {
      await prepared.cleanup();
    }

    final text = texts.join('\n\n').trim();
    if (text.isEmpty) {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.unknown,
        provider: 'SpokenLog',
        message: '전사 결과가 비어 있습니다.',
      );
    }
    return TranscriptionResult(
      text: text,
      segments: segments,
      durationSeconds: offset > 0 ? offset : null,
    );
  }

  Future<http.Response> _send(http.Request request) async {
    try {
      return await sendCloudRequest(request);
    } on TimeoutException {
      throw const TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'SpokenLog',
        message: 'SpokenLog 클라우드 응답 시간이 초과되었습니다.',
      );
    } on SocketException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'SpokenLog',
        message: '인터넷 연결 문제로 SpokenLog 클라우드에 접속하지 못했습니다.',
        detail: e.message,
      );
    } on http.ClientException catch (e) {
      throw TranscriptionException(
        kind: TranscriptionErrorKind.network,
        provider: 'SpokenLog',
        message: 'SpokenLog 클라우드 요청 중 네트워크 오류가 발생했습니다.',
        detail: e.message,
      );
    }
  }

  /// Error pages from proxies are not JSON; treat them as an empty body.
  static Map<String, dynamic> _json(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  TranscriptionException _error(http.Response response) {
    final status = response.statusCode;
    return TranscriptionException(
      kind: switch (status) {
        401 => TranscriptionErrorKind.authentication,
        413 => TranscriptionErrorKind.fileTooLarge,
        429 => TranscriptionErrorKind.rateLimit,
        >= 500 => TranscriptionErrorKind.serviceUnavailable,
        _ => TranscriptionErrorKind.invalidRequest,
      },
      provider: 'SpokenLog',
      statusCode: status,
      message: switch (status) {
        401 => 'Google 로그인이 만료되었습니다. 다시 로그인해 주세요.',
        >= 500 => 'SpokenLog 클라우드에 일시적인 문제가 있습니다. 잠시 후 다시 시도해 주세요.',
        _ => 'SpokenLog 클라우드가 요청을 처리하지 못했습니다.',
      },
    );
  }
}
