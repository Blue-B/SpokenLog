enum TranscriptionErrorKind {
  rateLimit,
  authentication,
  fileTooLarge,
  network,
  serviceUnavailable,
  invalidRequest,
  modelNotInstalled,
  unsupportedFormat,
  unknown,
}

class TranscriptionException implements Exception {
  const TranscriptionException({
    required this.kind,
    required this.message,
    this.provider,
    this.statusCode,
    this.retryAfterSeconds,
    this.detail,
  });

  final TranscriptionErrorKind kind;
  final String message;
  final String? provider;
  final int? statusCode;
  final int? retryAfterSeconds;
  final String? detail;

  bool get canFallback =>
      kind == TranscriptionErrorKind.rateLimit ||
      kind == TranscriptionErrorKind.network ||
      kind == TranscriptionErrorKind.serviceUnavailable;

  @override
  String toString() => message;
}
