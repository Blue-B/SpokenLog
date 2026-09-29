// Regression widget tests for the mobile recording-detail flow, playback
// stream refresh and cloud-credential prompt routing.
//
// These tests exercise the real [HomeScreen] widget with fake service/player
// classes. No real plugin channels, network or secure storage are used.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/models/recording_collection.dart';
import 'package:voice_transcriber/models/recording_item.dart';
import 'package:voice_transcriber/models/transcription_language.dart';
import 'package:voice_transcriber/models/transcription_provider.dart';
import 'package:voice_transcriber/models/transcription_result.dart';
import 'package:voice_transcriber/screens/home_screen.dart';
import 'package:voice_transcriber/services/recording_service.dart';
import 'package:voice_transcriber/services/settings_service.dart';
import 'package:voice_transcriber/services/wav_waveform_service.dart';
import 'package:voice_transcriber/widgets/app_settings_sheet.dart';
import 'package:voice_transcriber/widgets/cloud_credentials_dialog.dart';
import 'package:voice_transcriber/widgets/recording_details_sheet.dart';

// ---------------------------------------------------------------------------
// Synthetic WAV helper
// ---------------------------------------------------------------------------

/// Builds a valid 16-bit mono PCM WAV file so waveform/file-size code paths
/// read a real file instead of a placeholder.
Uint8List syntheticWav({int milliseconds = 3000, int sampleRate = 16000}) {
  final frameCount = (sampleRate * milliseconds / 1000).round();
  final dataSize = frameCount * 2;
  final bytes = BytesBuilder();
  void writeAscii(String value) => bytes.add(value.codeUnits);
  void writeUint32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(b.buffer.asUint8List());
  }

  void writeUint16(int value) {
    final b = ByteData(2)..setUint16(0, value, Endian.little);
    bytes.add(b.buffer.asUint8List());
  }

  writeAscii('RIFF');
  writeUint32(36 + dataSize);
  writeAscii('WAVE');
  writeAscii('fmt ');
  writeUint32(16);
  writeUint16(1); // PCM
  writeUint16(1); // mono
  writeUint32(sampleRate);
  writeUint32(sampleRate * 2); // byte rate
  writeUint16(2); // block align
  writeUint16(16); // bits per sample
  writeAscii('data');
  writeUint32(dataSize);
  // A quiet ramp so the waveform has non-zero peaks.
  for (var i = 0; i < frameCount; i++) {
    final sample = (i % 64) * 300 - 9600;
    writeUint16(sample & 0xFFFF);
  }
  return bytes.toBytes();
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

// These tests cover modal/playback state, not waveform sampling. A controlled
// reader avoids leaving real asynchronous WAV reads alive after fake-time tests,
// which otherwise locks fixture files on Windows during teardown.
class FakeWaveformService extends WavWaveformService {
  @override
  Future<List<double>> readPeaks(String path, {int bucketCount = 180}) async =>
      const [0.1, 0.4, 0.8, 0.3];
}

class FakeAudioPlayer implements AudioPlayer {
  final positionController = StreamController<Duration>.broadcast();
  final durationController = StreamController<Duration>.broadcast();
  final stateController = StreamController<PlayerState>.broadcast();
  final completeController = StreamController<void>.broadcast();

  final List<String> calls = <String>[];
  PositionUpdater? updater;
  PlayerState _state = PlayerState.stopped;
  bool disposed = false;

  @override
  Stream<Duration> get onPositionChanged => positionController.stream;

  @override
  Stream<Duration> get onDurationChanged => durationController.stream;

  @override
  Stream<PlayerState> get onPlayerStateChanged => stateController.stream;

  @override
  Stream<void> get onPlayerComplete => completeController.stream;

  @override
  PlayerState get state => _state;

  @override
  set positionUpdater(PositionUpdater? value) => updater = value;

  PositionUpdater? get positionUpdater => updater;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    calls.add('play:${source is DeviceFileSource ? source.path : source}');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> pause() async {
    calls.add('pause');
    _state = PlayerState.paused;
    if (!stateController.isClosed) stateController.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _state = PlayerState.playing;
    if (!stateController.isClosed) stateController.add(PlayerState.playing);
  }

  @override
  Future<void> setPlaybackRate(double playbackRate) async =>
      calls.add('rate:$playbackRate');

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async =>
      calls.add('releaseMode');

  @override
  Future<Duration?> getCurrentPosition() async => Duration.zero;

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    // Widget teardown cancels the subscriptions. Awaiting close while a
    // fake-async zone is paused can deadlock the test's own teardown.
    unawaited(positionController.close());
    unawaited(durationController.close());
    unawaited(stateController.close());
    unawaited(completeController.close());
    await updater?.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeSettingsService implements SettingsService {
  FakeSettingsService({
    this.provider = TranscriptionProvider.groq,
    this.language = TranscriptionLanguage.auto,
    this.apiKeys = const <TranscriptionProvider, String>{},
    this.accountId,
    this.appLanguage = 'ko',
    this.saveShouldThrow = false,
  });

  TranscriptionProvider provider;
  TranscriptionLanguage language;
  final Map<TranscriptionProvider, String> apiKeys;
  String? accountId;
  String appLanguage;
  bool saveShouldThrow;

  final List<String> savedApiKeys = <String>[];
  final List<String> savedAccountIds = <String>[];

  @override
  Future<TranscriptionProvider> getProvider() async => provider;

  @override
  Future<TranscriptionLanguage> getTranscriptionLanguage() async => language;

  final Map<TranscriptionProvider, String> savedModels = {};

  @override
  Future<String> getModel(TranscriptionProvider provider) async =>
      savedModels[provider] ?? provider.models.first;

  @override
  Future<void> setModel(TranscriptionProvider provider, String model) async {
    savedModels[provider] = model;
  }

  @override
  Future<void> setProvider(TranscriptionProvider value) async {
    provider = value;
  }

  @override
  Future<void> setTranscriptionLanguage(TranscriptionLanguage value) async {
    language = value;
  }

  @override
  Future<void> setSpeakerDiarizationEnabled(bool value) async {}

  @override
  Future<void> setSpeakerCount(int value) async {}

  @override
  Future<String?> getApiKey(TranscriptionProvider provider) async =>
      apiKeys[provider];

  @override
  Future<bool> hasApiKey(TranscriptionProvider provider) async {
    final value = apiKeys[provider];
    return value != null && value.trim().isNotEmpty;
  }

  @override
  Future<void> setApiKey(TranscriptionProvider provider, String value) async {
    if (saveShouldThrow) {
      throw Exception('secure storage write failed for sk-super-secret');
    }
    savedApiKeys.add(value);
    apiKeys[provider] = value;
  }

  @override
  Future<String?> getCloudflareAccountId() async => accountId;

  @override
  Future<void> setCloudflareAccountId(String value) async {
    savedAccountIds.add(value);
    accountId = value;
  }

  @override
  Future<String> getAppLanguage() async => appLanguage;

  @override
  Future<void> setAppLanguage(String value) async {
    if (saveShouldThrow) {
      throw PlatformException(code: '-25308', message: 'sk-super-secret');
    }
    appLanguage = value;
  }

  @override
  Future<bool> getSpeakerDiarizationEnabled() async => false;

  @override
  Future<int> getSpeakerCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeRecordingService implements RecordingService {
  FakeRecordingService(this._items, {this.collections = const []});

  List<RecordingItem> _items;
  List<RecordingCollection> collections;

  int loadCount = 0;

  @override
  Future<int> purgeExpiredTrash({
    Duration maxAge = const Duration(days: 30),
  }) async => 0;

  @override
  Future<List<RecordingItem>> loadRecordings() async {
    loadCount++;
    return List<RecordingItem>.of(_items);
  }

  @override
  Future<List<RecordingCollection>> loadCollections() async =>
      List<RecordingCollection>.of(collections);

  @override
  Future<void> renameRecording(RecordingItem item, String title) async {
    final normalized = title.trim();
    _items = _items
        .map(
          (entry) => entry.id == item.id
              ? entry.copyWith(title: normalized.isEmpty ? null : normalized)
              : entry,
        )
        .toList();
  }

  @override
  Future<void> setFavorite(RecordingItem item, bool value) async {
    _items = _items
        .map((entry) => entry.id == item.id
            ? entry.copyWith(isFavorite: value)
            : entry)
        .toList();
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

RecordingItem buildItem(
  String audioPath, {
  String id = 'rec-1',
  String? title = 'First clip',
  String? transcript,
  int durationMs = 3000,
  DateTime? createdAt,
}) {
  return RecordingItem(
    id: id,
    title: title,
    createdAt: createdAt ?? DateTime(2026, 9, 20, 10, 30),
    storagePath: File(audioPath).parent.path,
    chunks: [RecordingChunk(audioPath: audioPath, durationMs: durationMs)],
    transcript: transcript,
  );
}

Future<void> pumpHome(
  WidgetTester tester, {
  required FakeRecordingService recording,
  required FakeSettingsService settings,
  required FakeAudioPlayer player,
  Size size = const Size(390, 844),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: HomeScreen(
        recordingService: recording,
        settingsService: settings,
        audioPlayer: player,
        waveformService: FakeWaveformService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> openRecordingDetails(WidgetTester tester) async {
  await tester.tap(find.text('First clip').first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Finder inDetails(Finder matching) => find.descendant(
      of: find.byType(RecordingDetailsSheet),
      matching: matching,
    );

Future<void> startPlayback(WidgetTester tester) async {
  // Tap the play control inside the detail sheet (compact layout uses a
  // filled icon button labelled 재생). Targeting the descendant avoids
  // hitting the list tile rendered behind the modal barrier.
  final playButton = inDetails(find.byTooltip('재생'));
  expect(playButton, findsOneWidget);
  await tester.tap(playButton);
  await tester.pump();
  // The button callback's future is not awaited by the tappable and its
  // file-existence check needs real disk IO. Yield to the real event loop
  // outside runAsync's guarded zone, then pump the resulting state.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late Directory tempDir;
  late String wavPath;

  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spokenlog_widget_test');
    wavPath = '${tempDir.path}${Platform.pathSeparator}recording.wav';
    File(wavPath).writeAsBytesSync(syntheticWav());
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  for (final english in [false, true]) {
    testWidgets('one settings entry and direct transcription shortcut ($english)',
        (tester) async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => tempDir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = FakeAudioPlayer();
      addTearDown(player.dispose);
      await pumpHome(tester,
          recording: FakeRecordingService([buildItem(wavPath, transcript: 'Demo')]),
          settings: FakeSettingsService(appLanguage: english ? 'en' : 'ko'),
          player: player, size: const Size(1400, 900));
      final settingsLabel = english ? 'Settings' : '설정';
      final languageLabel = english ? 'Display language' : '표시 언어';
      expect(find.text(settingsLabel), findsOneWidget);
      expect(find.text(languageLabel), findsNothing);
      expect(find.text(english ? 'Speech recognition' : '음성 인식 설정'), findsNothing);
      await tester.tap(find.text(settingsLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsSheet), findsOneWidget);
      final language = find.byKey(const ValueKey('settings-display-language'));
      final cloud = find.byKey(const ValueKey('settings-groq'));
      expect(tester.getTopLeft(language).dy, lessThan(tester.getTopLeft(cloud).dy));
      await tester.tap(language);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AlertDialog, languageLabel), findsOneWidget);
      expect(find.byType(CloudCredentialsDialog), findsNothing);
      await tester.tap(find.text(english ? 'Cancel' : '취소'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(english ? 'Close' : '닫기'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(english ? 'Transcription settings' : '전사 설정'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AppSettingsSheet), findsNothing);
      expect(find.widgetWithText(AlertDialog,
          english ? 'Speech recognition settings' : '음성 인식 설정'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('language save failure stays visible and can be retried safely', (tester) async {
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    final settings = FakeSettingsService(saveShouldThrow: true);
    await pumpHome(tester, recording: FakeRecordingService([]),
        settings: settings, player: player);
    await tester.tap(find.byTooltip('설정').first);
    await tester.pumpAndSettle();
    final language = find.byKey(const ValueKey('settings-display-language'));
    await tester.ensureVisible(language);
    await tester.tap(language);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('설정을 저장하지 못했습니다'), findsOneWidget);
    expect(find.textContaining('sk-super-secret'), findsNothing);
    expect(settings.appLanguage, 'ko');
    expect(tester.takeException(), isNull);
    settings.saveShouldThrow = false;
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(settings.appLanguage, 'en');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final provider in [TranscriptionProvider.localSenseVoice,
      TranscriptionProvider.localWhisper,
      TranscriptionProvider.groq, TranscriptionProvider.cloudflare]) {
  testWidgets('English $provider settings localize modes, models and actions', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => tempDir.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    await pumpHome(tester,
        recording: FakeRecordingService([]),
        settings: FakeSettingsService(appLanguage: 'en',
            provider: provider),
        player: player);
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings-transcription'));
    await tester.ensureVisible(entry);
    await tester.runAsync(() async {
      await tester.tap(entry);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Recording language'), findsOneWidget);
    expect(find.text('Auto detect'), findsWidgets);
    expect(find.text('Process on this device'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
    expect(find.text('Processing mode'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    final texts = tester.widgetList<Text>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(Text)))
        .map((text) => text.data ?? '').where((text) => text != '한국어');
    expect(texts.where((text) => RegExp('[가-힣]').hasMatch(text)), isEmpty);
    expect(tester.takeException(), isNull);
  });

  }

  testWidgets('Whisper size can be chosen and the download size follows it', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => tempDir.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    await pumpHome(tester,
        recording: FakeRecordingService([]),
        settings: FakeSettingsService(appLanguage: 'en',
            provider: TranscriptionProvider.localWhisper),
        player: player);
    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings-transcription'));
    await tester.ensureVisible(entry);
    await tester.runAsync(() async {
      await tester.tap(entry);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.text('Whisper size'), findsOneWidget);
    expect(find.text('Download Whisper · about 104 MB'), findsOneWidget);

    final sizeField = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(sizeField);
    await tester.pumpAndSettle();
    await tester.tap(sizeField);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Whisper Base INT8').last);
    await tester.pumpAndSettle();
    // The size change checks the model files, which is real disk I/O.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    expect(find.text('Download Whisper · about 161 MB'), findsOneWidget);
    expect(find.text('Download Whisper · about 104 MB'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved Whisper size is the one transcription looks for', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => tempDir.path);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    final settings = FakeSettingsService(appLanguage: 'en',
        provider: TranscriptionProvider.localWhisper);
    await pumpHome(tester,
        recording: FakeRecordingService([buildItem(wavPath, transcript: null)]),
        settings: settings, player: player);

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings-transcription'));
    await tester.ensureVisible(entry);
    await tester.runAsync(() async {
      await tester.tap(entry);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    final sizeField = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(sizeField);
    await tester.pumpAndSettle();
    await tester.tap(sizeField);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Whisper Base INT8').last);
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(settings.savedModels[TranscriptionProvider.localWhisper],
        'whisper-base-multilingual-int8');

    // The settings sheet stays open behind the dialog; close it like a user.
    await tester.tap(find.byTooltip('Close').first);
    await tester.pumpAndSettle();

    // Nothing is installed in the test sandbox, so transcription stops with a
    // message naming the size it looked for. It must be Base, not Tiny.
    await openRecordingDetails(tester);
    await tester.tap(find.byKey(const ValueKey('transcribe-rec-1')));
    await tester.pump();
    // The service reads the WAV header and model folder from disk, so give the
    // real event loop time to finish before looking at the message.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Whisper base').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('Whisper base'), findsWidgets);
    expect(find.textContaining('Whisper tiny'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English transcript and active playback labels stay English', (tester) async {
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    final item = buildItem(wavPath, transcript: 'Synthetic demo').copyWith(
      segments: const [TranscriptSegment(startSeconds: 0, endSeconds: 1,
          text: 'Synthetic demo')],
    );
    await pumpHome(tester,
        recording: FakeRecordingService([item]),
        settings: FakeSettingsService(appLanguage: 'en'), player: player,
        size: const Size(1400, 900));
    expect(find.text('1 segment'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Play').last);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    player.stateController.add(PlayerState.playing);
    await tester.pump();
    expect(find.text('Playing at 1.0×'), findsOneWidget);
    expect(find.textContaining('재생 중'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synthetic fixture is a readable WAV', (tester) async {
    expect(File(wavPath).existsSync(), isTrue);
    expect(File(wavPath).lengthSync(), greaterThan(44));
    expect(File(wavPath).readAsBytesSync().sublist(0, 4), 'RIFF'.codeUnits);
  });

  testWidgets('mobile record detail opens and playback stream events move '
      'the detail slider', (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);

    // The HomeScreen installed a real TimerPositionUpdater on the player.
    expect(player.positionUpdater, isA<TimerPositionUpdater>());

    await openRecordingDetails(tester);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
    final sliderFinder = find.byKey(const ValueKey('playback-slider-rec-1'));
    expect(sliderFinder, findsOneWidget);

    // Activate playback so the sheet's slider becomes interactive.
    await startPlayback(tester);
    expect(player.calls.any((call) => call.startsWith('play:')), isTrue);

    // A real duration event should extend the timeline.
    player.durationController.add(const Duration(milliseconds: 6000));
    await tester.pump();

    // A position event emitted on the player stream must update the modal
    // slider (this is the auto-refresh regression: a modal route does not
    // rebuild from the page behind it).
    player.positionController.add(const Duration(milliseconds: 3000));
    await tester.pump();

    Slider slider() => tester.widget<Slider>(sliderFinder);
    expect(slider().value, closeTo(0.5, 0.02));

    player.positionController.add(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(slider().value, closeTo(0.25, 0.02));

    // Player state changes should update the visible pause/play affordance.
    player.stateController.add(PlayerState.playing);
    await tester.pump();
    expect(find.byTooltip('일시정지'), findsWidgets);
  });

  testWidgets('pause, resume and slider seek drive the player', (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);
    await startPlayback(tester);

    player.durationController.add(const Duration(milliseconds: 4000));
    player.stateController.add(PlayerState.playing);
    await tester.pump();

    // Pause.
    await tester.tap(inDetails(find.byTooltip('일시정지')));
    await tester.pump();
    expect(player.calls, contains('pause'));

    // Resume.
    await tester.tap(inDetails(find.byTooltip('재생')));
    await tester.pump();
    expect(player.calls, contains('resume'));

    // Seek via the slider's onChangeEnd.
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('playback-slider-rec-1')),
    );
    slider.onChangeStart?.call(0.75);
    slider.onChanged?.call(0.75);
    await tester.runAsync(() async {
      slider.onChangeEnd?.call(0.75);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // A seek replays from the target position, so another play call is issued.
    final playCalls =
        player.calls.where((call) => call.startsWith('play:')).length;
    expect(playCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('detail sheet follows HomeScreen data refreshes (rename)',
      (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
    expect(find.text('First clip'), findsWidgets);

    // Use the in-sheet management menu to rename, which triggers _reload.
    await tester.tap(find.byTooltip('기록 메뉴').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('이름 변경').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(find.byType(TextField).last, 'Renamed session');
    await tester.tap(find.text('저장'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The still-open detail sheet must show the refreshed title.
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
    expect(find.text('Renamed session'), findsWidgets);
  });

  testWidgets('missing Groq key opens CloudCredentialsDialog above the '
      'recording sheet with inline validation and cancel', (tester) async {
    final item = buildItem(wavPath, transcript: null);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService(
      provider: TranscriptionProvider.groq,
      language: TranscriptionLanguage.auto,
    );
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);

    // Tapping transcribe must prompt for credentials immediately.
    await tester.tap(find.byKey(const ValueKey('transcribe-rec-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(CloudCredentialsDialog), findsOneWidget);
    // The recording sheet is still present underneath.
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);

    // Empty save shows inline validation instead of leaving the dialog.
    await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
    await tester.pump();
    expect(find.byType(CloudCredentialsDialog), findsOneWidget);
    expect(find.text('API 키를 입력해 주세요.'), findsOneWidget);
    expect(settings.savedApiKeys, isEmpty);

    // Cancel returns to the same recording sheet.
    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CloudCredentialsDialog), findsNothing);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
  });

  testWidgets('repeated transcribe taps do not stack credential prompts',
      (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService(provider: TranscriptionProvider.groq);
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);

    final transcribeButton = find.byKey(const ValueKey('transcribe-rec-1'));
    await tester.tap(transcribeButton);
    await tester.pump();
    await tester.tap(transcribeButton, warnIfMissed: false);
    await tester.pump();
    await tester.tap(transcribeButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(CloudCredentialsDialog), findsOneWidget);
  });

  testWidgets('credential storage errors stay in the dialog and do not leak '
      'the secret', (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService(
      provider: TranscriptionProvider.groq,
      saveShouldThrow: true,
    );
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);
    await tester.tap(find.byKey(const ValueKey('transcribe-rec-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CloudCredentialsDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('cloud-api-key')),
      'sk-super-secret',
    );
    await tester.tap(find.byKey(const ValueKey('save-cloud-credentials')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Dialog remains open with a generic error.
    expect(find.byType(CloudCredentialsDialog), findsOneWidget);
    expect(
      find.text('인증 정보를 저장하지 못했습니다. 다시 시도해 주세요.'),
      findsOneWidget,
    );
    // The underlying secret must not be echoed back to the UI.
    expect(find.byWidgetPredicate((widget) => widget is Text &&
        (widget.data ?? '').contains('sk-super-secret')), findsNothing);
    expect(tester.widget<EditableText>(find.descendant(
        of: find.byType(CloudCredentialsDialog),
        matching: find.byType(EditableText))).obscureText, isTrue);
    // The dialog must still be above the recording sheet.
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
  });

  testWidgets('settings hub exposes direct API, model and display-language '
      'entries', (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);

    await tester.tap(find.byTooltip('설정').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AppSettingsSheet), findsOneWidget);

    for (final key in const [
      'settings-groq',
      'settings-cloudflare',
      'settings-local-models',
      'settings-transcription',
      'settings-display-language',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }

    // Groq entry opens the credentials dialog directly.
    await tester.ensureVisible(find.byKey(const ValueKey('settings-groq')));
    await tester.tap(find.byKey(const ValueKey('settings-groq')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(CloudCredentialsDialog), findsOneWidget);
  });

  for (final scale in [1.0, 1.8]) {
    testWidgets('recording language label stays inside settings viewport at $scale',
        (tester) async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => tempDir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final player = FakeAudioPlayer();
      addTearDown(player.dispose);
      await pumpHome(tester,
          recording: FakeRecordingService([buildItem(wavPath)]),
          settings: FakeSettingsService(), player: player,
          textScale: scale,
          theme: ThemeData(inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          )));
      await tester.tap(find.byTooltip('설정').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('settings-transcription')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('settings-transcription')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      final scroll = find.descendant(of: dialog,
          matching: find.byType(SingleChildScrollView));
      final label = find.descendant(of: dialog, matching: find.text('녹음 언어'));
      expect(label, findsOneWidget);
      expect(tester.getTopLeft(label).dy,
          greaterThanOrEqualTo(tester.getTopLeft(scroll).dy),
          reason: 'The floating label must not paint above the clipped viewport');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('select all respects search and wraps actions at narrow mobile width', (tester) async {
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);
    await pumpHome(tester, recording: FakeRecordingService([
      buildItem(wavPath), buildItem(wavPath, id: 'rec-2', title: 'Second clip'),
    ]), settings: FakeSettingsService(), player: player,
        size: const Size(320, 844), textScale: 1.8);
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-all-visible')));
    await tester.pumpAndSettle();
    expect(find.text('2개 선택'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'First');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-all-visible')));
    await tester.pumpAndSettle();
    expect(find.text('1개 선택'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-all-visible')));
    await tester.pumpAndSettle();
    expect(find.text('0개 선택'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow width and large text scale keep the detail flow usable',
      (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();
    addTearDown(player.dispose);

    await pumpHome(
      tester,
      recording: recording,
      settings: settings,
      player: player,
      size: const Size(390, 844),
      textScale: 1.8,
    );

    await openRecordingDetails(tester);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('playback-slider-rec-1')),
      findsOneWidget,
    );

    // No RenderFlex overflow should have been reported.
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing HomeScreen disposes the injected player and leaves '
      'no open subscriptions', (tester) async {
    final item = buildItem(wavPath);
    final recording = FakeRecordingService([item]);
    final settings = FakeSettingsService();
    final player = FakeAudioPlayer();

    await pumpHome(tester, recording: recording, settings: settings,
        player: player);
    await openRecordingDetails(tester);
    expect(find.byType(RecordingDetailsSheet), findsOneWidget);

    // Tear the whole tree down while the modal is open.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(player.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
