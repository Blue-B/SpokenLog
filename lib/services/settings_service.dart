import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/transcription_language.dart';
import '../models/transcription_provider.dart';

class SettingsService {
  static const _providerKey = 'transcription_provider';
  static const _groqApiKey = 'groq_api_key';
  static const _cloudflareApiToken = 'cloudflare_api_token';
  static const _cloudflareAccountId = 'cloudflare_account_id';
  static const _groqModelKey = 'groq_whisper_model';
  static const _whisperModelKey = 'local_whisper_model';
  static const _transcriptionLanguageKey = 'transcription_language';
  static const _speakerDiarizationEnabledKey = 'speaker_diarization_enabled';
  static const _speakerCountKey = 'speaker_count';
  static const _appLanguageKey = 'app_language';

  static const _groqUsageDateKey = 'groq_usage_date';
  static const _groqUsageSecondsKey = 'groq_usage_seconds';
  static const _groqRemainingRequestsKey = 'groq_remaining_requests';
  static const _groqLimitRequestsKey = 'groq_limit_requests';
  static const _groqQuotaUpdatedAtKey = 'groq_quota_updated_at';

  static const _cloudflareUsageDateKey = 'cloudflare_usage_date';
  static const _cloudflareUsageSecondsKey = 'cloudflare_usage_seconds';

  // Ad-hoc macOS downloads cannot use the provisioning-only shared keychain.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );


  Future<void> clearAppSettings() async {
    // Delete only this app's keys, not other entries in a shared Keychain.
    for (final key in const [
      _providerKey, _groqApiKey, _cloudflareApiToken, _cloudflareAccountId,
      _groqModelKey, _whisperModelKey, _transcriptionLanguageKey, _speakerDiarizationEnabledKey,
      _speakerCountKey, _appLanguageKey, _groqUsageDateKey, _groqUsageSecondsKey,
      _groqRemainingRequestsKey, _groqLimitRequestsKey, _groqQuotaUpdatedAtKey,
      _cloudflareUsageDateKey, _cloudflareUsageSecondsKey,
    ]) {
      await _storage.delete(key: key);
    }
  }

  Future<String> getAppLanguage() async {
    final value = await _storage.read(key: _appLanguageKey);
    return switch (value) {
      'ko' => 'ko',
      'en' => 'en',
      _ => 'system',
    };
  }

  Future<void> setAppLanguage(String value) {
    final normalized = const {'system', 'ko', 'en'}.contains(value)
        ? value
        : 'system';
    return _storage.write(key: _appLanguageKey, value: normalized);
  }

  Future<TranscriptionProvider> getProvider() async {
    return TranscriptionProvider.fromId(
      await _storage.read(key: _providerKey),
    );
  }

  Future<void> setProvider(TranscriptionProvider provider) {
    return _storage.write(key: _providerKey, value: provider.id);
  }

  Future<String?> getApiKey(TranscriptionProvider provider) {
    return switch (provider) {
      TranscriptionProvider.groq => _storage.read(key: _groqApiKey),
      TranscriptionProvider.cloudflare =>
        _storage.read(key: _cloudflareApiToken),
      TranscriptionProvider.localSenseVoice ||
      TranscriptionProvider.localWhisper => Future.value(null),
    };
  }

  Future<bool> hasApiKey(TranscriptionProvider provider) async {
    final value = await getApiKey(provider);
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> setApiKey(
    TranscriptionProvider provider,
    String value,
  ) async {
    if (provider.isLocal) return;

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('API 키가 비어 있습니다.');
    }

    final key = provider == TranscriptionProvider.groq
        ? _groqApiKey
        : _cloudflareApiToken;
    await _storage.write(key: key, value: trimmed);
  }

  Future<void> deleteApiKey(TranscriptionProvider provider) async {
    if (provider.isLocal) return;
    final key = provider == TranscriptionProvider.groq
        ? _groqApiKey
        : _cloudflareApiToken;
    await _storage.delete(key: key);
  }

  Future<String?> getCloudflareAccountId() {
    return _storage.read(key: _cloudflareAccountId);
  }

  Future<void> setCloudflareAccountId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _cloudflareAccountId);
    } else {
      await _storage.write(key: _cloudflareAccountId, value: trimmed);
    }
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _todayKey() => _dateKey(DateTime.now());

  String _utcTodayKey() => _dateKey(DateTime.now().toUtc());

  Future<int> _getDailySeconds({
    required String dateKey,
    required String secondsKey,
  }) async {
    final today = _todayKey();
    final savedDate = await _storage.read(key: dateKey);

    if (savedDate != today) {
      await _storage.write(key: dateKey, value: today);
      await _storage.write(key: secondsKey, value: '0');
      return 0;
    }

    return int.tryParse(
          await _storage.read(key: secondsKey) ?? '0',
        ) ??
        0;
  }

  Future<void> _addDailySeconds({
    required String dateKey,
    required String secondsKey,
    required int seconds,
  }) async {
    if (seconds <= 0) return;
    final current = await _getDailySeconds(
      dateKey: dateKey,
      secondsKey: secondsKey,
    );
    await _storage.write(
      key: secondsKey,
      value: (current + seconds).toString(),
    );
  }

  Future<int> getGroqUsageSecondsToday() {
    return _getDailySeconds(
      dateKey: _groqUsageDateKey,
      secondsKey: _groqUsageSecondsKey,
    );
  }

  Future<void> addGroqUsageSeconds(int seconds) {
    return _addDailySeconds(
      dateKey: _groqUsageDateKey,
      secondsKey: _groqUsageSecondsKey,
      seconds: seconds,
    );
  }

  Future<int> getCloudflareUsageSecondsToday() async {
    final utcToday = _utcTodayKey();
    final savedDate =
        await _storage.read(key: _cloudflareUsageDateKey);

    if (savedDate != utcToday) {
      await _storage.write(
        key: _cloudflareUsageDateKey,
        value: utcToday,
      );
      await _storage.write(
        key: _cloudflareUsageSecondsKey,
        value: '0',
      );
      return 0;
    }

    return int.tryParse(
          await _storage.read(key: _cloudflareUsageSecondsKey) ?? '0',
        ) ??
        0;
  }

  Future<void> addCloudflareUsageSeconds(int seconds) async {
    if (seconds <= 0) return;
    final current = await getCloudflareUsageSecondsToday();
    await _storage.write(
      key: _cloudflareUsageSecondsKey,
      value: (current + seconds).toString(),
    );
  }

  Future<void> saveGroqRequestQuota({
    required int? remainingRequests,
    required int? limitRequests,
  }) async {
    if (remainingRequests != null) {
      await _storage.write(
        key: _groqRemainingRequestsKey,
        value: remainingRequests.toString(),
      );
    }
    if (limitRequests != null) {
      await _storage.write(
        key: _groqLimitRequestsKey,
        value: limitRequests.toString(),
      );
    }
    await _storage.write(
      key: _groqQuotaUpdatedAtKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<int?> getGroqRemainingRequests() async {
    return int.tryParse(
      await _storage.read(key: _groqRemainingRequestsKey) ?? '',
    );
  }

  Future<int?> getGroqLimitRequests() async {
    return int.tryParse(
      await _storage.read(key: _groqLimitRequestsKey) ?? '',
    );
  }

  Future<DateTime?> getGroqQuotaUpdatedAt() async {
    return DateTime.tryParse(
      await _storage.read(key: _groqQuotaUpdatedAtKey) ?? '',
    );
  }

  Future<TranscriptionLanguage> getTranscriptionLanguage() async {
    return TranscriptionLanguage.fromId(
      await _storage.read(key: _transcriptionLanguageKey),
    );
  }

  Future<void> setTranscriptionLanguage(
    TranscriptionLanguage language,
  ) {
    return _storage.write(
      key: _transcriptionLanguageKey,
      value: language.storageId,
    );
  }

  Future<bool> getSpeakerDiarizationEnabled() async {
    return (await _storage.read(key: _speakerDiarizationEnabledKey)) == '1';
  }

  Future<void> setSpeakerDiarizationEnabled(bool value) {
    return _storage.write(
      key: _speakerDiarizationEnabledKey,
      value: value ? '1' : '0',
    );
  }

  Future<int> getSpeakerCount() async {
    final value = int.tryParse(
      await _storage.read(key: _speakerCountKey) ?? '0',
    );
    if (value == null || value < 0 || value > 8) return 0;
    return value;
  }

  Future<void> setSpeakerCount(int value) {
    final normalized = value < 0 || value > 8 ? 0 : value;
    return _storage.write(
      key: _speakerCountKey,
      value: normalized.toString(),
    );
  }

  Future<String> getModel(TranscriptionProvider provider) async {
    final key = switch (provider) {
      TranscriptionProvider.groq => _groqModelKey,
      TranscriptionProvider.localWhisper => _whisperModelKey,
      _ => null,
    };
    if (key == null) return provider.models.first;

    final saved = await _storage.read(key: key);
    if (saved != null && provider.models.contains(saved)) {
      return saved;
    }
    return provider.models.first;
  }

  Future<void> setModel(
    TranscriptionProvider provider,
    String model,
  ) async {
    if (!provider.models.contains(model)) {
      throw ArgumentError('지원하지 않는 전사 모델입니다.');
    }

    if (provider == TranscriptionProvider.groq) {
      await _storage.write(key: _groqModelKey, value: model);
    } else if (provider == TranscriptionProvider.localWhisper) {
      await _storage.write(key: _whisperModelKey, value: model);
    }
  }
}
