import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Downloads [uri] to [target] through `<target>.part`, resuming with an HTTP
/// Range request when the connection drops mid-file.
///
/// Model CDNs and mobile networks often close long transfers part-way
/// ("Connection closed while receiving data"); without resuming, a 40-240 MB
/// model download would restart from zero or fail outright.
Future<void> downloadWithResume(
  Uri uri,
  File target, {
  required void Function(double? progress) onProgress,
  int attempts = 5,
  Duration stallTimeout = const Duration(seconds: 60),
  Duration Function(int attempt) retryDelay = _defaultDelay,
}) async {
  final part = File('${target.path}.part');
  if (await part.exists()) await part.delete();

  for (var attempt = 1; ; attempt++) {
    final client = http.Client();
    IOSink? sink;
    try {
      final offset = await part.exists() ? await part.length() : 0;
      final request = http.Request('GET', uri);
      if (offset > 0) request.headers['range'] = 'bytes=$offset-';
      final response = await client.send(request);

      // 206 continues the partial file; 200 means the server ignored Range.
      final resumed = offset > 0 && response.statusCode == 206;
      if (!resumed &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        throw DownloadStatusException(response.statusCode);
      }
      final start = resumed ? offset : 0;
      final length = response.contentLength;
      final total = length == null || length <= 0 ? null : start + length;

      sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var received = start;
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total == null ? null : received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total != null && received < total) {
        throw const HttpException(
          'Download ended before the full file arrived',
        );
      }

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return;
    } catch (e) {
      final retryable = e is! DownloadStatusException || e.isRetryable;
      if (!retryable || attempt >= attempts) rethrow;
    } finally {
      await sink?.close();
      client.close();
    }
    await Future<void>.delayed(retryDelay(attempt));
  }
}

Duration _defaultDelay(int attempt) => Duration(seconds: 2 * attempt);

class DownloadStatusException implements Exception {
  const DownloadStatusException(this.statusCode);

  final int statusCode;

  bool get isRetryable =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  @override
  String toString() => '모델 다운로드에 실패했습니다 (HTTP $statusCode).';
}
