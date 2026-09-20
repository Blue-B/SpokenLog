import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/transcription_error.dart';

void main() {
  test('rate limit errors can fall back', () {
    const error = TranscriptionException(
      kind: TranscriptionErrorKind.rateLimit,
      message: 'limit',
    );
    expect(error.canFallback, isTrue);
  });

  test('authentication errors do not silently fall back', () {
    const error = TranscriptionException(
      kind: TranscriptionErrorKind.authentication,
      message: 'auth',
    );
    expect(error.canFallback, isFalse);
  });

  test('network and service failures can fall back', () {
    const network = TranscriptionException(
      kind: TranscriptionErrorKind.network,
      message: 'network',
    );
    const service = TranscriptionException(
      kind: TranscriptionErrorKind.serviceUnavailable,
      message: 'service',
    );

    expect(network.canFallback, isTrue);
    expect(service.canFallback, isTrue);
  });
}
