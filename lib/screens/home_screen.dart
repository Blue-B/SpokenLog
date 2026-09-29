import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/recording_collection.dart';
import '../models/recording_item.dart';
import '../models/transcription_result.dart';
import '../models/transcription_error.dart';
import '../models/transcription_language.dart';
import '../models/transcription_provider.dart';
import '../services/cloudflare_transcription_service.dart';
import '../services/groq_transcription_service.dart';
import '../services/sensevoice_model_manager.dart';
import '../services/sensevoice_transcription_service.dart';
import '../services/speaker_diarization_model_manager.dart';
import '../services/speaker_diarization_service.dart';
import '../services/whisper_model_manager.dart';
import '../services/whisper_transcription_service.dart';
import '../services/wav_waveform_service.dart';
import '../services/recording_service.dart';
import '../services/settings_service.dart';
import '../services/transcript_export_service.dart';
import '../utils/formatters.dart';
import '../widgets/transcript_editor_dialog.dart';
import '../widgets/mobile_library_widgets.dart';
import '../widgets/app_settings_sheet.dart';
import '../widgets/cloud_credentials_dialog.dart';
import '../widgets/cloud_connection_help.dart';
import '../widgets/drag_selection_list.dart';
import '../widgets/storage_management_dialog.dart';
import '../widgets/recording_details_sheet.dart';

enum _WorkspaceView { records, calendar }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.recordingService, this.settingsService,
    this.audioPlayer, this.waveformService});

  final RecordingService? recordingService;
  final SettingsService? settingsService;
  final AudioPlayer? audioPlayer;
  final WavWaveformService? waveformService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _recording = widget.recordingService ?? RecordingService();
  late final _settings = widget.settingsService ?? SettingsService();
  final _transcriptExport = TranscriptExportService();
  final _groq = GroqTranscriptionService();
  final _cloudflare = CloudflareTranscriptionService();
  final _senseVoiceModelManager = SenseVoiceModelManager();
  final _whisperModelManager = WhisperModelManager();
  final _speakerDiarizationModelManager =
      SpeakerDiarizationModelManager();
  late final _waveformService = widget.waveformService ?? WavWaveformService();
  final Map<String, Future<List<double>>> _waveformFutures = {};
  late final SenseVoiceTranscriptionService _senseVoice;
  late final WhisperTranscriptionService _whisper;
  late final SpeakerDiarizationService _speakerDiarization;
  late final _player = widget.audioPlayer ?? AudioPlayer();
  final _searchController = TextEditingController();
  bool _viewActive = true;
  final _recordingDetailChanges = ValueNotifier<int>(0);
  final _detailMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _settingsMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final Set<String> _pendingTranscription = <String>{};

  List<RecordingItem> _items = const [];
  List<RecordingCollection> _collections = const [];
  bool _isRecording = false;
  bool _startingRecording = false;
  bool _isPausedRecording = false;
  bool _loading = true;
  bool _importingFiles = false;
  bool _draggingFiles = false;
  bool _trashCleanupDone = false;
  String _query = '';
  TranscriptionProvider _provider = TranscriptionProvider.groq;
  TranscriptionLanguage _language = TranscriptionLanguage.auto;
  String _model = TranscriptionProvider.groq.models.first;
  String? _selectedRecordingId;
  String _libraryScope = 'all';
  bool get _collectionFolderOpen => _currentCollectionId != null;
  bool _calendarWeekView = false;
  bool _selectionMode = false;
  final Set<String> _batchSelectedIds = <String>{};
  _WorkspaceView _workspaceView = _WorkspaceView.records;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedCalendarDate = DateTime.now();
  String _appLanguage = 'system';

  final Set<String> _transcribing = <String>{};
  final Map<String, String> _transcribingProgress = <String, String>{};
  final Set<String> _expandedTranscripts = <String>{};
  bool _batchTranscriptionRunning = false;
  int _batchTranscriptionCompleted = 0;
  int _batchTranscriptionTotal = 0;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<void>? _completeSubscription;

  RecordingItem? _activePlayback;
  int _activeChunkIndex = 0;
  Duration _activeChunkDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackTotal = Duration.zero;
  bool _isPlayingAudio = false;
  bool _draggingPlayback = false;
  Duration _dragPosition = Duration.zero;
  bool _handlingCompletion = false;
  double _playbackRate = 1.0;

  Timer? _recordingTicker;
  DateTime? _recordingStartedAt;
  DateTime? _recordingPausedAt;
  Duration _recordingPausedDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _senseVoice = SenseVoiceTranscriptionService(_senseVoiceModelManager);
    _whisper = WhisperTranscriptionService(_whisperModelManager);
    _speakerDiarization =
        SpeakerDiarizationService(_speakerDiarizationModelManager);
    _initPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_reload());
    });
    unawaited(_loadTranscriptionPreference());
    unawaited(_loadUiPreferences());
  }

  /// Keeps the Whisper model manager on the size saved in settings.
  Future<void> _syncWhisperSize() async {
    _whisperModelManager.size = WhisperModelSize.fromModelId(
      await _settings.getModel(TranscriptionProvider.localWhisper),
    );
  }

  Future<void> _loadTranscriptionPreference() async {
    await _syncWhisperSize();
    final provider = await _settings.getProvider();
    final language = await _settings.getTranscriptionLanguage();
    final model = await _settings.getModel(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _language = language;
      _model = model;
    });
  }

  Future<void> _loadUiPreferences() async {
    final language = await _settings.getAppLanguage();
    if (!mounted) return;
    setState(() => _appLanguage = language);
  }

  bool get _useEnglish {
    if (_appLanguage == 'en') return true;
    if (_appLanguage == 'ko') return false;
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en';
  }

  String _t(String ko, String en) => _useEnglish ? en : ko;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<RecordingItem> _itemsForDate(DateTime date) => _scopeItems()
      .where((item) => _sameDay(item.createdAt.toLocal(), date))
      .toList();

  TranscriptionLanguage _compatibleLanguage(
    TranscriptionProvider provider,
    TranscriptionLanguage current,
  ) {
    if (provider.supportsLanguage(current)) return current;
    for (final candidate in TranscriptionLanguage.values) {
      if (provider.supportsLanguage(candidate)) return candidate;
    }
    return TranscriptionLanguage.auto;
  }

  void _refreshRecordingViews(VoidCallback update) {
    if (!mounted || !_viewActive) return;
    setState(update);
    _recordingDetailChanges.value++;
  }

  void _initPlayer() {
    // Read the native playback clock rather than estimating elapsed wall time.
    // Updates do not depend on animation frames in the route behind the modal.
    _player.positionUpdater = TimerPositionUpdater(
      getPosition: _player.getCurrentPosition,
      interval: const Duration(milliseconds: 100),
    );
    unawaited(_player.setReleaseMode(ReleaseMode.stop));

    _positionSubscription = _player.onPositionChanged.listen((position) {
      final item = _activePlayback;
      if (item == null || _draggingPlayback || !mounted) return;
      final globalPosition = _chunkOffset(item, _activeChunkIndex) + position;
      _refreshRecordingViews(() => _playbackPosition = globalPosition);
    });

    _durationSubscription = _player.onDurationChanged.listen((duration) {
      final item = _activePlayback;
      if (item == null || !mounted) return;
      _refreshRecordingViews(() {
        _activeChunkDuration = duration;
        if (item.chunks.length == 1 && duration > Duration.zero) {
          _playbackTotal = duration;
        }
      });
    });

    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      _refreshRecordingViews(() => _isPlayingAudio = state == PlayerState.playing);
    });

    _completeSubscription = _player.onPlayerComplete.listen((_) {
      unawaited(_handlePlaybackComplete());
    });
  }

  Future<void> _reload() async {
    try {
      if (!_trashCleanupDone) {
        _trashCleanupDone = true;
        await _recording.purgeExpiredTrash();
      }
      final items = await _recording.loadRecordings();
      final collections = await _recording.loadCollections();
      if (!mounted) return;
      _refreshRecordingViews(() {
        _items = items;
        _collections = collections;
        _loading = false;

        _batchSelectedIds.removeWhere(
          (id) => !items.any((item) => item.id == id),
        );

        final selectedStillExists = _selectedRecordingId != null &&
            items.any((item) => item.id == _selectedRecordingId);
        if (!selectedStillExists) {
          final visible = _scopeItems(items);
          _selectedRecordingId = visible.isEmpty ? null : visible.first.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('녹음 목록을 불러오지 못했습니다: $e', error: true);
    }
  }

  Duration get _liveRecordingDuration {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return Duration.zero;

    final end = _recordingPausedAt ?? DateTime.now();
    final elapsed = end.difference(startedAt) - _recordingPausedDuration;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void _startRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording) setState(() {});
    });
  }

  void _resetRecordingClock() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
    _recordingStartedAt = null;
    _recordingPausedAt = null;
    _recordingPausedDuration = Duration.zero;
  }

  Future<void> _startRecording() async {
    if (_startingRecording || _isRecording) return;
    _startingRecording = true;
    try {
      await _stopPlayback();
      await _recording.start();
      if (!mounted) {
        await _recording.stop();
        return;
      }

      setState(() {
        _isRecording = true;
        _isPausedRecording = false;
        _recordingStartedAt = DateTime.now();
        _recordingPausedAt = null;
        _recordingPausedDuration = Duration.zero;
      });
      _startRecordingTicker();
    } catch (e) {
      _message(e.toString(), error: true);
    } finally {
      _startingRecording = false;
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recording.stop();
      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _isPausedRecording = false;
      });
      _resetRecordingClock();
      await _reload();
      _message('녹음을 안전하게 저장했습니다.');
    } catch (e) {
      if (!await _recording.isRecording() && mounted) {
        setState(() {
          _isRecording = false;
          _isPausedRecording = false;
        });
        _resetRecordingClock();
      }
      _message(e.toString(), error: true);
    }
  }

  Future<void> _toggleRecordingPause() async {
    if (!_isRecording) return;

    try {
      if (_isPausedRecording) {
        await _recording.resume();
        final pausedAt = _recordingPausedAt;
        if (pausedAt != null) {
          _recordingPausedDuration += DateTime.now().difference(pausedAt);
        }
        if (!mounted) return;
        setState(() {
          _isPausedRecording = false;
          _recordingPausedAt = null;
        });
      } else {
        await _recording.pause();
        if (!mounted) return;
        setState(() {
          _isPausedRecording = true;
          _recordingPausedAt = DateTime.now();
        });
      }
    } catch (e) {
      _message('녹음 상태를 변경하지 못했습니다: $e', error: true);
    }
  }

  Duration _chunkOffset(RecordingItem item, int chunkIndex) {
    var milliseconds = 0;
    for (var i = 0; i < chunkIndex && i < item.chunks.length; i++) {
      milliseconds += item.chunks[i].durationMs;
    }
    return Duration(milliseconds: milliseconds);
  }

  Duration _localPlaybackPosition(RecordingItem item) {
    final offset = _chunkOffset(item, _activeChunkIndex);
    final localMs = _playbackPosition.inMilliseconds - offset.inMilliseconds;
    return Duration(milliseconds: localMs.clamp(0, 1 << 31).toInt());
  }

  ({int chunkIndex, Duration localPosition}) _resolveSeekTarget(
    RecordingItem item,
    Duration target,
  ) {
    if (item.chunks.length <= 1 ||
        !item.chunks.every((chunk) => chunk.durationMs > 0)) {
      return (chunkIndex: 0, localPosition: target);
    }

    var remaining = target.inMilliseconds;
    for (var i = 0; i < item.chunks.length; i++) {
      final chunkMs = item.chunks[i].durationMs;
      if (remaining <= chunkMs || i == item.chunks.length - 1) {
        return (
          chunkIndex: i,
          localPosition: Duration(
            milliseconds: remaining.clamp(0, chunkMs).toInt(),
          ),
        );
      }
      remaining -= chunkMs;
    }

    return (chunkIndex: 0, localPosition: Duration.zero);
  }

  Future<void> _togglePlayback(RecordingItem item) async {
    if (_isRecording) return;

    try {
      final active = _activePlayback?.id == item.id;

      if (!active) {
        await _playFrom(item, Duration.zero);
        return;
      }

      if (_isPlayingAudio) {
        await _player.pause();
        return;
      }

      final totalMs = _playbackTotal.inMilliseconds;
      final atEnd = totalMs > 0 &&
          _playbackPosition.inMilliseconds >= totalMs - 250;
      if (atEnd) {
        await _playFrom(item, Duration.zero);
        return;
      }

      if (_player.state == PlayerState.paused) {
        await _player.resume();
        await _player.setPlaybackRate(_playbackRate);
        return;
      }

      await _playChunk(
        item,
        _activeChunkIndex,
        position: _localPlaybackPosition(item),
      );
    } catch (e) {
      _message('재생하지 못했습니다: $e', error: true);
    }
  }

  Future<void> _playFrom(
    RecordingItem item,
    Duration target, {
    bool autoPlay = true,
  }) async {
    if (item.chunks.isEmpty) {
      throw Exception('재생할 녹음 파일이 없습니다.');
    }

    var targetMs = target.inMilliseconds;
    final knownTotalMs = _activePlayback?.id == item.id &&
            _playbackTotal > Duration.zero
        ? _playbackTotal.inMilliseconds : item.duration.inMilliseconds;
    if (knownTotalMs > 0) {
      targetMs = targetMs.clamp(0, knownTotalMs).toInt();
    } else if (targetMs < 0) {
      targetMs = 0;
    }

    final resolved = _resolveSeekTarget(
      item,
      Duration(milliseconds: targetMs),
    );

    await _player.stop();
    if (!mounted) return;
    _refreshRecordingViews(() {
      _activePlayback = item;
      _activeChunkIndex = resolved.chunkIndex;
      _activeChunkDuration = Duration.zero;
      _playbackPosition = Duration(milliseconds: targetMs);
      _playbackTotal = Duration(milliseconds: knownTotalMs);
      _draggingPlayback = false;
      _dragPosition = Duration.zero;
    });

    await _playChunk(
      item,
      resolved.chunkIndex,
      position: resolved.localPosition,
      autoPlay: autoPlay,
    );
  }

  Future<void> _playChunk(
    RecordingItem item,
    int index, {
    Duration position = Duration.zero,
    bool autoPlay = true,
  }) async {
    if (index < 0 || index >= item.chunks.length) return;

    final path = item.chunks[index].audioPath;
    if (!await File(path).exists()) {
      throw Exception('녹음 파일을 찾을 수 없습니다.');
    }

    if (mounted) {
      _refreshRecordingViews(() {
        _activePlayback = item;
        _activeChunkIndex = index;
        _activeChunkDuration = Duration.zero;
        _playbackPosition = _chunkOffset(item, index) + position;
        if (item.durationMs > 0 && (item.chunks.length > 1 ||
            _playbackTotal <= Duration.zero)) {
          _playbackTotal = item.duration;
        }
      });
    }

    await _player.play(DeviceFileSource(path), position: position);
    await _player.setPlaybackRate(_playbackRate);
    if (!autoPlay) {
      await _player.pause();
    }
  }

  Future<void> _handlePlaybackComplete() async {
    if (_handlingCompletion) return;
    final item = _activePlayback;
    if (item == null) return;

    _handlingCompletion = true;
    try {
      final nextIndex = _activeChunkIndex + 1;
      if (nextIndex < item.chunks.length) {
        await _playChunk(item, nextIndex);
        return;
      }

      if (!mounted) return;
      final fallbackEnd = _chunkOffset(item, _activeChunkIndex) +
          (_activeChunkDuration > Duration.zero
              ? _activeChunkDuration
              : Duration(
                  milliseconds: item.chunks[_activeChunkIndex].durationMs,
                ));
      _refreshRecordingViews(() {
        _isPlayingAudio = false;
        _playbackPosition =
            _playbackTotal > Duration.zero ? _playbackTotal : fallbackEnd;
      });
    } finally {
      _handlingCompletion = false;
    }
  }

  Future<void> _seekPlayback(
    RecordingItem item,
    Duration target, {
    bool forcePlay = false,
  }) async {
    try {
      final active = _activePlayback?.id == item.id;
      final wasPlaying = active ? _isPlayingAudio : forcePlay;

      if (!active) {
        await _playFrom(item, target, autoPlay: forcePlay);
        return;
      }

      _refreshRecordingViews(() {
        _draggingPlayback = false;
        _playbackPosition = target;
      });
      await _playFrom(item, target, autoPlay: wasPlaying);
    } catch (e) {
      _message('재생 위치를 변경하지 못했습니다: $e', error: true);
    }
  }

  Future<void> _setPlaybackRate(double value) async {
    _refreshRecordingViews(() => _playbackRate = value);
    if (_activePlayback != null) {
      try {
        await _player.setPlaybackRate(value);
      } catch (e) {
        _message('재생 속도를 변경하지 못했습니다: $e', error: true);
      }
    }
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (!mounted) return;
    _refreshRecordingViews(() {
      _activePlayback = null;
      _activeChunkIndex = 0;
      _activeChunkDuration = Duration.zero;
      _playbackPosition = Duration.zero;
      _playbackTotal = Duration.zero;
      _isPlayingAudio = false;
      _draggingPlayback = false;
      _dragPosition = Duration.zero;
    });
  }

  Future<void> _transcribe(
    RecordingItem item, {
    TranscriptionProvider? providerOverride,
    bool announceCompletion = true,
  }) async {
    if (_pendingTranscription.contains(item.id) ||
        _transcribing.contains(item.id) || item.isDeleted) return;
    _refreshRecordingViews(() => _pendingTranscription.add(item.id));
    try {
      await _performTranscription(item,
          providerOverride: providerOverride,
          announceCompletion: announceCompletion);
    } catch (_) {
      _message(_t('전사를 준비하지 못했습니다. 연결 설정을 확인해 주세요.',
          'Could not prepare transcription. Check your connection settings.'),
          error: true);
    } finally {
      _refreshRecordingViews(() => _pendingTranscription.remove(item.id));
    }
  }

  Future<void> _performTranscription(
    RecordingItem item, {
    TranscriptionProvider? providerOverride,
    bool announceCompletion = true,
  }) async {
    final provider = providerOverride ?? await _settings.getProvider();
    final language = await _settings.getTranscriptionLanguage();
    if (!mounted) return;
    final model = await _settings.getModel(provider);

    if (!provider.supportsLanguage(language)) {
      _message(
        '${provider.label}은(는) ${language.label}을 지원하지 않습니다. '
        '전사 설정에서 다른 엔진이나 언어를 선택해 주세요.',
        error: true,
      );
      return;
    }

    String? apiKey;
    String? cloudflareAccountId;

    if (provider.requiresApiKey) {
      apiKey = await _settings.getApiKey(provider);
      if (apiKey == null || apiKey.trim().isEmpty) {
        final saved = await _showCloudCredentials(provider,
            resumeTranscription: true);
        if (!saved || !mounted) return;
        apiKey = await _settings.getApiKey(provider);
        if (apiKey == null || apiKey.trim().isEmpty) return;
      }
    }

    if (provider == TranscriptionProvider.cloudflare) {
      cloudflareAccountId = await _settings.getCloudflareAccountId();
      if (cloudflareAccountId == null ||
          cloudflareAccountId.trim().isEmpty) {
        final saved = await _showCloudCredentials(provider,
            resumeTranscription: true);
        if (!saved || !mounted) return;
        cloudflareAccountId = await _settings.getCloudflareAccountId();
        apiKey = await _settings.getApiKey(provider);
        if (cloudflareAccountId == null || cloudflareAccountId.trim().isEmpty ||
            apiKey == null || apiKey.trim().isEmpty) return;
      }
    }

    if (!mounted) return;
    _refreshRecordingViews(() {
      _provider = provider;
      _model = model;
      _transcribing.add(item.id);
      _transcribingProgress[item.id] = provider.isLocal
          ? _t('기기에서 로컬 전사를 준비하고 있습니다.', 'Preparing on-device transcription...')
          : _t('전사를 준비하고 있습니다.', 'Preparing transcription...');
    });

    TranscriptionProvider? fallback;

    try {
      void progress(int completed, int total) {
        if (!mounted) return;
        _refreshRecordingViews(() {
          _transcribingProgress[item.id] =
              _t('$completed / $total 조각 전사 완료', '$completed / $total chunks transcribed');
        });
      }

      var result = switch (provider) {
        TranscriptionProvider.groq => await _groq.transcribeRecording(
            recording: item,
            apiKey: apiKey!,
            model: model,
            language: language,
            onProgress: progress,
          ),
        TranscriptionProvider.cloudflare =>
          await _cloudflare.transcribeRecording(
            recording: item,
            accountId: cloudflareAccountId!,
            apiToken: apiKey!,
            language: language,
            onProgress: progress,
          ),
        TranscriptionProvider.localSenseVoice =>
          await _senseVoice.transcribeRecording(
            recording: item,
            language: language,
          ),
        TranscriptionProvider.localWhisper =>
          await _whisper.transcribeRecording(
            recording: item,
            language: language,
          ),
      };

      String? diarizationNote;
      final diarizationEnabled =
          await _settings.getSpeakerDiarizationEnabled();

      if (diarizationEnabled) {
        if (result.segments.isEmpty) {
          diarizationNote =
              ' · 이 엔진은 현재 시간 구간이 없어 화자 라벨을 붙이지 못했습니다.';
        } else if (!await _speakerDiarizationModelManager.isInstalled()) {
          diarizationNote =
              ' · 화자 구분 모델이 설치되지 않아 화자 라벨을 생략했습니다.';
        } else {
          try {
            if (mounted) {
              _refreshRecordingViews(() {
                _transcribingProgress[item.id] =
                    '로컬에서 화자를 구분하고 있습니다.';
              });
            }

            final speakerCount = await _settings.getSpeakerCount();
            final turns = await _speakerDiarization.diarizeRecording(
              recording: item,
              numSpeakers: speakerCount,
              onProgress: (value) {
                if (!mounted) return;
                _refreshRecordingViews(() {
                  _transcribingProgress[item.id] =
                      '화자 구분 ${(value * 100).round()}%';
                });
              },
            );

            result = _speakerDiarization.attachSpeakers(
              transcription: result,
              turns: turns,
            );
          } catch (e) {
            diarizationNote = ' · 화자 구분은 실패했지만 전사문은 저장했습니다.';
          }
        }
      }

      await _recording.saveTranscript(item, result);

      final seconds = result.durationSeconds?.round() ??
          (item.durationMs > 0 ? item.duration.inSeconds : 0);

      if (provider == TranscriptionProvider.groq) {
        await _settings.addGroqUsageSeconds(seconds);
        final quota = _groq.lastQuota;
        await _settings.saveGroqRequestQuota(
          remainingRequests: quota?.remainingRequests,
          limitRequests: quota?.limitRequests,
        );
      } else if (provider == TranscriptionProvider.cloudflare) {
        await _settings.addCloudflareUsageSeconds(seconds);
      }

      await _reload();
      _expandedTranscripts.add(item.id);

      final quota = provider == TranscriptionProvider.groq
          ? _groq.lastQuota
          : null;
      final quotaText = quota?.remainingRequests != null
          ? ' · 일일 요청 잔여 ${quota!.remainingRequests}회'
          : '';

      if (announceCompletion) {
        _message(
          '${_t('${provider.shortLabel} · ${language.label} 전사가 완료되었습니다.', '${provider.shortLabel} · ${language.displayLabel(useEnglish: true)} transcription complete.')}'
          '$quotaText${diarizationNote ?? ''}',
        );
      }
    } on TranscriptionException catch (e) {
      if (e.canFallback) {
        fallback = await _chooseFallbackProvider(
          failedProvider: provider,
          error: e,
        );
      } else {
        final detail = e.detail;
        _message(
          detail == null || detail.isEmpty
              ? e.message
              : '${e.message}\n$detail',
          error: true,
        );

        if (e.kind == TranscriptionErrorKind.modelNotInstalled) {
          await _openSettings(initialProvider: provider);
        }
      }
    } catch (e) {
      _message('전사 중 예상하지 못한 오류가 발생했습니다: $e', error: true);
    } finally {
      if (mounted) {
        _refreshRecordingViews(() {
          _transcribing.remove(item.id);
          _transcribingProgress.remove(item.id);
        });
      }
    }

    if (fallback != null && mounted) {
      await _performTranscription(
        item,
        providerOverride: fallback,
        announceCompletion: announceCompletion,
      );
    }
  }

  Future<TranscriptionProvider?> _chooseFallbackProvider({
    required TranscriptionProvider failedProvider,
    required TranscriptionException error,
  }) async {
    final language = await _settings.getTranscriptionLanguage();
    final senseVoiceReady = await _senseVoiceModelManager.isInstalled();
    final whisperReady = await _whisperModelManager.isInstalled();
    final cloudflareReady =
        await _settings.hasApiKey(TranscriptionProvider.cloudflare) &&
        ((await _settings.getCloudflareAccountId())?.trim().isNotEmpty ??
            false);
    final groqReady =
        await _settings.hasApiKey(TranscriptionProvider.groq);

    if (!mounted) return null;

    bool usable(TranscriptionProvider value, bool ready) {
      return ready &&
          value != failedProvider &&
          value.supportsLanguage(language);
    }

    final title = switch (error.kind) {
      TranscriptionErrorKind.rateLimit => '사용 한도에 도달했습니다',
      TranscriptionErrorKind.network => '네트워크 연결에 문제가 있습니다',
      TranscriptionErrorKind.serviceUnavailable =>
        '전사 서비스가 일시적으로 불안정합니다',
      _ => '전사를 완료하지 못했습니다',
    };

    return showDialog<TranscriptionProvider>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error.message),
              if (error.detail != null && error.detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  error.detail!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '현재 음성 언어: ${language.label}\n'
                '설치·설정되어 있고 이 언어를 지원하는 다른 엔진으로 바로 다시 시도할 수 있습니다.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_openSettings());
            },
            icon: const Icon(Icons.settings_outlined),
            label: const Text('전사 설정'),
          ),
          if (usable(TranscriptionProvider.groq, groqReady))
            OutlinedButton(
              onPressed: () => Navigator.pop(
                context,
                TranscriptionProvider.groq,
              ),
              child: const Text('Groq'),
            ),
          if (usable(TranscriptionProvider.cloudflare, cloudflareReady))
            OutlinedButton(
              onPressed: () => Navigator.pop(
                context,
                TranscriptionProvider.cloudflare,
              ),
              child: const Text('Cloudflare'),
            ),
          if (usable(
            TranscriptionProvider.localSenseVoice,
            senseVoiceReady,
          ))
            OutlinedButton(
              onPressed: () => Navigator.pop(
                context,
                TranscriptionProvider.localSenseVoice,
              ),
              child: const Text('SenseVoice'),
            ),
          if (usable(
            TranscriptionProvider.localWhisper,
            whisperReady,
          ))
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                TranscriptionProvider.localWhisper,
              ),
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Local Whisper'),
            ),
        ],
      ),
    );
  }

  Future<void> _showQuickTranscriptionPanel() async {
    var provider = await _settings.getProvider();
    var language = await _settings.getTranscriptionLanguage();
    var model = await _settings.getModel(provider);
    // Switching engines must keep each engine's saved model, not reset it.
    final savedModels = {
      for (final value in TranscriptionProvider.values)
        value: await _settings.getModel(value),
    };
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t('빠른 음성 인식 설정', 'Quick speech settings'),
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  _t(
                    '녹음 언어와 음성을 글자로 바꾸는 방식을 빠르게 바꿀 수 있습니다. 연결 정보나 모델 관리는 세부 설정에서 할 수 있습니다.',
                    'Quickly change the recording language and how speech is converted to text. Connections and model management are available in More settings.',
                  ),
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<TranscriptionProvider>(
                  value: provider,
                  decoration: InputDecoration(
                    labelText: _t('음성 인식 방식', 'Speech recognition'),
                    prefixIcon: Icon(
                      provider.isLocal
                          ? Icons.computer_rounded
                          : Icons.cloud_queue_rounded,
                    ),
                  ),
                  items: TranscriptionProvider.values
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry,
                          child: Text(entry.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next == null) return;
                    setSheetState(() {
                      provider = next;
                      language = _compatibleLanguage(provider, language);
                      model = savedModels[provider]!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TranscriptionLanguage>(
                  value: language,
                  decoration: InputDecoration(
                    labelText: _t('녹음 언어', 'Recording language'),
                    prefixIcon: const Icon(Icons.translate_rounded),
                  ),
                  items: TranscriptionLanguage.values
                      .where(provider.supportsLanguage)
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry,
                          child: Text(entry.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) {
                      setSheetState(() => language = next);
                    }
                  },
                ),
                if (provider == TranscriptionProvider.groq) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: model,
                    decoration: InputDecoration(
                      labelText: _t('모델', 'Model'),
                      prefixIcon: const Icon(Icons.tune_rounded),
                    ),
                    items: provider.models
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry,
                            child: Text(provider.modelLabel(entry, useEnglish: _useEnglish)),
                          ),
                        )
                        .toList(),
                    onChanged: (next) {
                      if (next != null) setSheetState(() => model = next);
                    },
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        unawaited(_openSettings(initialProvider: provider));
                      },
                      icon: const Icon(Icons.language_rounded),
                      label: Text(_t('세부 설정', 'More settings')),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await _settings.setProvider(provider);
                        await _settings.setTranscriptionLanguage(language);
                        await _settings.setModel(provider, model);
                        await _syncWhisperSize();
                        if (!mounted) return;
                        setState(() {
                          _provider = provider;
                          _language = language;
                          _model = model;
                        });
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      child: Text(_t('적용', 'Apply')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showEnginePanel() async {
    final installed = <TranscriptionProvider, bool>{
      TranscriptionProvider.localSenseVoice:
          await _senseVoiceModelManager.isInstalled(),
      TranscriptionProvider.localWhisper:
          await _whisperModelManager.isInstalled(),
      TranscriptionProvider.groq:
          await _settings.hasApiKey(TranscriptionProvider.groq),
      TranscriptionProvider.cloudflare:
          await _settings.hasApiKey(TranscriptionProvider.cloudflare) &&
              ((await _settings.getCloudflareAccountId())?.trim().isNotEmpty ??
                  false),
    };
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('음성 인식 방식 선택', 'Choose speech recognition'),
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                '준비가 끝난 방식을 바로 선택할 수 있습니다.',
                'Choose any speech recognition option that is ready to use.',
              ),
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ...TranscriptionProvider.values.map((entry) {
              final ready = installed[entry] ?? false;
              final selected = entry == _provider;
              return Card(
                margin: const EdgeInsets.only(bottom: 7),
                child: ListTile(
                  leading: Icon(
                    entry.isLocal
                        ? Icons.computer_rounded
                        : Icons.cloud_queue_rounded,
                  ),
                  title: Text(
                    entry.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    ready
                        ? _t(
                            '사용 가능 · ${entry.privacyLabel}',
                            'Ready · ${entry.privacyLabel}',
                          )
                        : _t('설치 또는 인증 필요', 'Setup required'),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_circle_rounded)
                      : ready
                          ? const Icon(Icons.chevron_right_rounded)
                          : const Icon(Icons.settings_outlined),
                  onTap: () async {
                    if (!ready) {
                      Navigator.pop(sheetContext);
                      unawaited(_openSettings(initialProvider: entry));
                      return;
                    }
                    final nextLanguage =
                        _compatibleLanguage(entry, _language);
                    final nextModel = await _settings.getModel(entry);
                    await _settings.setProvider(entry);
                    await _settings.setTranscriptionLanguage(nextLanguage);
                    if (!mounted) return;
                    setState(() {
                      _provider = entry;
                      _language = nextLanguage;
                      _model = nextModel;
                    });
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<bool> _showCloudCredentials(
    TranscriptionProvider provider, {
    bool resumeTranscription = false,
  }) async {
    final key = await _settings.getApiKey(provider) ?? '';
    final accountId = provider == TranscriptionProvider.cloudflare
        ? await _settings.getCloudflareAccountId() ?? '' : '';
    if (!mounted) return false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CloudCredentialsDialog(
        providerName: provider.shortLabel,
        initialKey: key,
        initialAccountId: accountId,
        needsAccountId: provider == TranscriptionProvider.cloudflare,
        resumeTranscription: resumeTranscription,
        useEnglish: _useEnglish,
        onSave: (value, account) async {
          if (provider == TranscriptionProvider.cloudflare) {
            await _settings.setCloudflareAccountId(account);
          }
          await _settings.setApiKey(provider, value);
        },
      ),
    );
    if (saved == true) {
      _refreshRecordingViews(() {});
      if (!resumeTranscription) {
        _message(_t('인증 정보를 저장했습니다.', 'Credentials saved.'));
      }
    }
    return saved == true;
  }

  Future<void> _showAppSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.86,
        child: ScaffoldMessenger(
          key: _settingsMessengerKey,
          child: Scaffold(
            backgroundColor: Theme.of(sheetContext).colorScheme.surface,
            body: ListenableBuilder(
              listenable: _recordingDetailChanges,
              builder: (_, _) => !mounted || !_viewActive
                  ? const SizedBox.shrink() : AppSettingsSheet(
                useEnglish: _useEnglish,
                onGroq: () => unawaited(_showCloudCredentials(TranscriptionProvider.groq)),
                onCloudflare: () => unawaited(_showCloudCredentials(TranscriptionProvider.cloudflare)),
                onLocalModels: () => unawaited(_openSettings(
                    initialProvider: _provider.isLocal
                        ? _provider : TranscriptionProvider.localSenseVoice)),
                onTranscription: () => unawaited(_openSettings()),
                onDisplayLanguage: () => unawaited(_showLanguageSettings()),
                onStorage: () => unawaited(_showStorageManagement()),
                onLicenses: () => showLicensePage(
                  context: context,
                  applicationName: 'SpokenLog',
                  applicationLegalese:
                      'AGPL-3.0-only. Speech models are downloaded separately; '
                      'their licenses are listed below.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showStorageManagement() async {
    if (_loading || _isRecording || _startingRecording || _importingFiles ||
        _transcribing.isNotEmpty || _pendingTranscription.isNotEmpty || _batchTranscriptionRunning) {
      _message(_t('녹음, 가져오기, 전사가 끝난 뒤 정리해 주세요.',
          'Wait for recording, import and transcription to finish.'), error: true);
      return;
    }
    await _stopPlayback();
    if (!mounted) return;
    await showDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => StorageManagementDialog(
          onClearSettings: _settings.clearAppSettings, useEnglish: _useEnglish));
    if (!mounted) return;
    _clearBatchSelection();
    await _reload();
    await _loadTranscriptionPreference();
    await _loadUiPreferences();
  }

  Future<void> _showLanguageSettings() async {
    var value = await _settings.getAppLanguage();
    if (!mounted) return;
    var saving = false;
    String? saveError;

    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(_t('표시 언어', 'Display language')),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _t(
                    '메뉴와 버튼에 표시되는 언어를 선택합니다. 녹음 속 언어 설정과는 별개입니다.',
                    'Choose the language used for menus and buttons. This is separate from the language spoken in your recordings.',
                  ),
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  value: 'system',
                  groupValue: value,
                  title: Text(_t('시스템 기본값', 'System default')),
                  onChanged: (next) =>
                      setDialogState(() => value = next ?? value),
                ),
                RadioListTile<String>(
                  value: 'ko',
                  groupValue: value,
                  title: const Text('한국어'),
                  onChanged: (next) =>
                      setDialogState(() => value = next ?? value),
                ),
                RadioListTile<String>(
                  value: 'en',
                  groupValue: value,
                  title: const Text('English'),
                  onChanged: (next) =>
                      setDialogState(() => value = next ?? value),
                ),
                if (saveError != null)
                  Text(saveError!, style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(_t('취소', 'Cancel')),
            ),
            FilledButton(
              onPressed: saving ? null : () async {
                final selected = value;
                setDialogState(() { saving = true; saveError = null; });
                try {
                  await _settings.setAppLanguage(selected);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, selected);
                  }
                } catch (_) {
                  if (dialogContext.mounted) {
                    setDialogState(() {
                      saving = false;
                      saveError = _t(
                        '설정을 저장하지 못했습니다. 보안 저장소 잠금과 접근 권한을 확인한 뒤 다시 시도해 주세요.',
                        'Could not save settings. Check that secure storage is unlocked and accessible, then try again.',
                      );
                    });
                  }
                }
              },
              child: Text(_t('저장', 'Save')),
            ),
          ],
        ),
      ),
    );

    if (saved != null && mounted) {
      _refreshRecordingViews(() => _appLanguage = saved);
    }
  }

  Future<void> _openSettings({
    TranscriptionProvider? initialProvider,
  }) async {
    final currentProvider =
        initialProvider ?? await _settings.getProvider();
    final currentLanguage = await _settings.getTranscriptionLanguage();
    final currentDiarizationEnabled =
        await _settings.getSpeakerDiarizationEnabled();
    final currentSpeakerCount = await _settings.getSpeakerCount();

    final groqKey =
        await _settings.getApiKey(TranscriptionProvider.groq) ?? '';
    final cloudflareToken =
        await _settings.getApiKey(TranscriptionProvider.cloudflare) ?? '';
    final cloudflareAccountId =
        await _settings.getCloudflareAccountId() ?? '';
    final groqModel =
        await _settings.getModel(TranscriptionProvider.groq);

    var senseVoiceInstalled =
        await _senseVoiceModelManager.isInstalled();
    await _syncWhisperSize();
    var whisperInstalled = await _whisperModelManager.isInstalled();
    var whisperModelValue = _whisperModelManager.size.modelId;
    var diarizationInstalled =
        await _speakerDiarizationModelManager.isInstalled();

    if (!mounted) return;

    final groqController = TextEditingController(text: groqKey);
    final cloudflareTokenController =
        TextEditingController(text: cloudflareToken);
    final cloudflareAccountController =
        TextEditingController(text: cloudflareAccountId);

    var provider = currentProvider;
    var language = currentLanguage;
    var showLocalProviders = provider.isLocal;
    var groqModelValue = groqModel;
    var diarizationEnabled = currentDiarizationEnabled;
    var speakerCount = currentSpeakerCount;
    var obscureKey = true;
    String? downloadingTask;
    double? modelProgress;
    String? settingsNotice;
    bool settingsNoticeIsError = false;

    if (!provider.supportsLanguage(language)) {
      // Opening a model's settings must not silently jump to a cloud provider.
      language = _compatibleLanguage(provider, language);
    }

    final hasKey = <TranscriptionProvider, bool>{
      TranscriptionProvider.groq: groqKey.trim().isNotEmpty,
      TranscriptionProvider.cloudflare:
          cloudflareToken.trim().isNotEmpty,
      TranscriptionProvider.localSenseVoice: false,
      TranscriptionProvider.localWhisper: false,
    };

    final settingsScrollController = ScrollController();
    var settingsScrollInitialized = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          final scheme = Theme.of(dialogContext).colorScheme;
          final isDownloading = downloadingTask != null;
          final dialogSize = MediaQuery.sizeOf(dialogContext);
          final compactSettings = dialogSize.width < 700;
          final compactContentHeight = (
            dialogSize.height -
            MediaQuery.paddingOf(dialogContext).vertical -
            MediaQuery.viewInsetsOf(dialogContext).bottom - 220
          ).clamp(120.0, 760.0).toDouble();

          if (!settingsScrollInitialized) {
            settingsScrollInitialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (settingsScrollController.hasClients) {
                settingsScrollController.jumpTo(0);
              }
            });
          }

          void notice(String message, {bool error = false}) {
            if (!dialogContext.mounted) return;
            setLocalState(() {
              settingsNotice = message;
              settingsNoticeIsError = error;
            });
          }

          TextEditingController? activeKeyController;
          String? keyLabel;
          String? keyHint;

          if (provider == TranscriptionProvider.groq) {
            activeKeyController = groqController;
            keyLabel = 'Groq API Key';
            keyHint = 'gsk_...';
          } else if (provider == TranscriptionProvider.cloudflare) {
            activeKeyController = cloudflareTokenController;
            keyLabel = 'Cloudflare API Token';
            keyHint = _t('Workers AI 권한이 있는 토큰', 'Token with Workers AI permission');
          }

          final keyRegistered = hasKey[provider] ?? false;

          Future<void> installLocalModel(
            TranscriptionProvider target,
          ) async {
            setLocalState(() {
              downloadingTask = target.id;
              modelProgress = null;
            });

            try {
              switch (target) {
                case TranscriptionProvider.localSenseVoice:
                  await _senseVoiceModelManager.download(
                    onProgress: (progress, _) {
                      if (!dialogContext.mounted) return;
                      setLocalState(() => modelProgress = progress);
                    },
                  );
                  if (!dialogContext.mounted) return;
                  setLocalState(() => senseVoiceInstalled = true);
                case TranscriptionProvider.localWhisper:
                  await _whisperModelManager.download(
                    onProgress: (progress, _) {
                      if (!dialogContext.mounted) return;
                      setLocalState(() => modelProgress = progress);
                    },
                  );
                  if (!dialogContext.mounted) return;
                  setLocalState(() => whisperInstalled = true);
                case TranscriptionProvider.groq:
                case TranscriptionProvider.cloudflare:
                  return;
              }

              notice(_t('${target.shortLabel} 모델 설치가 완료되었습니다.', '${target.shortLabel} model installed.'));
            } catch (e) {
              notice(
                '${target.shortLabel} 모델 다운로드에 실패했습니다: $e',
                error: true,
              );
            } finally {
              if (dialogContext.mounted) {
                setLocalState(() {
                  downloadingTask = null;
                  modelProgress = null;
                });
              }
            }
          }

          Future<void> deleteLocalModel(
            TranscriptionProvider target,
          ) async {
            switch (target) {
              case TranscriptionProvider.localSenseVoice:
                await _senseVoiceModelManager.deleteModel();
                if (!dialogContext.mounted) return;
                setLocalState(() => senseVoiceInstalled = false);
              case TranscriptionProvider.localWhisper:
                await _whisperModelManager.deleteModel();
                if (!dialogContext.mounted) return;
                setLocalState(() => whisperInstalled = false);
              case TranscriptionProvider.groq:
              case TranscriptionProvider.cloudflare:
                return;
            }
          }

          Future<void> installDiarizationModel() async {
            setLocalState(() {
              downloadingTask = 'speaker_diarization';
              modelProgress = null;
            });

            try {
              await _speakerDiarizationModelManager.download(
                onProgress: (progress, _) {
                  if (!dialogContext.mounted) return;
                  setLocalState(() => modelProgress = progress);
                },
              );

              if (!dialogContext.mounted) return;
              setLocalState(() => diarizationInstalled = true);
              notice(_t('로컬 화자 구분 모델 설치가 완료되었습니다.', 'Local speaker models installed.'));
            } catch (e) {
              notice(
                '화자 구분 모델 다운로드에 실패했습니다: $e',
                error: true,
              );
            } finally {
              if (dialogContext.mounted) {
                setLocalState(() {
                  downloadingTask = null;
                  modelProgress = null;
                });
              }
            }
          }

          Future<void> deleteDiarizationModel() async {
            await _speakerDiarizationModelManager.deleteModel();
            if (!dialogContext.mounted) return;
            setLocalState(() {
              diarizationInstalled = false;
              diarizationEnabled = false;
            });
          }

          bool localInstalled(TranscriptionProvider value) {
            return switch (value) {
              TranscriptionProvider.localSenseVoice => senseVoiceInstalled,
              TranscriptionProvider.localWhisper => whisperInstalled,
              _ => false,
            };
          }

          void selectProviderMode(bool isLocal) {
            final candidates = TranscriptionProvider.values
                .where(
                  (value) =>
                      value.isLocal == isLocal &&
                      value.supportsLanguage(language),
                )
                .toList();

            TranscriptionProvider? next;
            if (isLocal) {
              for (final candidate in candidates) {
                if (localInstalled(candidate)) {
                  next = candidate;
                  break;
                }
              }
            }

            if (next == null && candidates.isNotEmpty) {
              next = candidates.first;
            }

            final selectedProvider = next;
            if (selectedProvider == null) return;

            setLocalState(() {
              showLocalProviders = isLocal;
              provider = selectedProvider;
              obscureKey = true;
            });
          }

          Widget modeChoice({
            required bool isLocal,
            required String title,
            required String subtitle,
            required IconData icon,
            bool expanded = true,
          }) {
            final selected = showLocalProviders == isLocal;

            final card = Material(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: isDownloading
                    ? null
                    : () => selectProviderMode(isLocal),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 82),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: Theme.of(dialogContext)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                if (selected) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 17,
                                    color: scheme.primary,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            return expanded ? Expanded(child: card) : card;
          }

          Widget modeSelector() {
            final stacked =
                MediaQuery.sizeOf(dialogContext).width < 560;

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  modeChoice(
                    isLocal: false,
                    title: _t('온라인으로 처리', 'Process online'),
                    subtitle: _t('빠른 처리 · 인터넷 연결 필요', 'Fast processing · Internet required'),
                    icon: Icons.cloud_queue_rounded,
                    expanded: false,
                  ),
                  const SizedBox(height: 8),
                  modeChoice(
                    isLocal: true,
                    title: _t('이 기기에서 처리', 'Process on this device'),
                    subtitle: _t('음성 외부 전송 없음 · 사용 제한 없음', 'No audio uploads · No usage quota'),
                    icon: Icons.computer_rounded,
                    expanded: false,
                  ),
                ],
              );
            }

            return Row(
              children: [
                modeChoice(
                  isLocal: false,
                  title: _t('온라인으로 처리', 'Process online'),
                  subtitle: _t('빠른 처리 · 인터넷 연결 필요', 'Fast processing · Internet required'),
                  icon: Icons.cloud_queue_rounded,
                ),
                const SizedBox(width: 10),
                modeChoice(
                  isLocal: true,
                  title: _t('이 기기에서 처리', 'Process on this device'),
                  subtitle: _t('음성 외부 전송 없음 · 사용 제한 없음', 'No audio uploads · No usage quota'),
                  icon: Icons.computer_rounded,
                ),
              ],
            );
          }

          Widget providerCard(TranscriptionProvider value) {
            final selected = value == provider;
            final supported = value.supportsLanguage(language);
            final installed =
                value.isLocal ? localInstalled(value) : null;

            return _SttProviderCard(
              provider: value,
              useEnglish: _useEnglish,
              selected: selected,
              installed: installed,
              supported: supported,
              enabled: !isDownloading,
              onTap: () {
                if (!supported) return;
                setLocalState(() {
                  provider = value;
                  obscureKey = true;
                });
              },
            );
          }

          Widget usagePanel() {
            if (!provider.isLocal) {
              return CloudConnectionHelp(
                cloudflare: provider == TranscriptionProvider.cloudflare,
                useEnglish: _useEnglish,
              );
            }

            return _UsagePanel(
              title: _t('기기에서 처리', 'On-device processing'),
              progress: null,
              primaryText: _t('전사 횟수와 시간 제한 없음', 'No transcription count or duration quota'),
              secondaryText: _t(
                  '인터넷이나 API 키 없이 기기 안에서 처리합니다. '
                  '처리 속도는 기기 성능에 따라 달라질 수 있습니다.',
                  'Runs on your device without internet or an API key. Speed depends on your hardware.'),
            );
          }

          Widget localModelPanel() {
            if (!provider.isLocal) return const SizedBox.shrink();

            final installed = localInstalled(provider);
            final sizeLabel = switch (provider) {
              TranscriptionProvider.localSenseVoice => _t('약 239MB', 'about 239 MB'),
              TranscriptionProvider.localWhisper => _t(
                    '약 ${_whisperModelManager.size.downloadMegabytes}MB',
                    'about ${_whisperModelManager.size.downloadMegabytes} MB'),
              _ => '',
            };
            final downloading = downloadingTask == provider.id;

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        installed
                            ? Icons.check_circle_outline_rounded
                            : Icons.download_for_offline_outlined,
                        color: installed
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          installed
                              ? _t('${provider.shortLabel} 모델이 설치되어 있습니다.', '${provider.shortLabel} is installed.')
                              : _t('${provider.shortLabel} 모델 다운로드가 필요합니다 · $sizeLabel', 'Download ${provider.shortLabel} · $sizeLabel'),
                          style:
                              Theme.of(dialogContext).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: modelProgress),
                    const SizedBox(height: 6),
                    Text(
                      modelProgress == null
                          ? _t('다운로드 중...', 'Downloading...')
                          : _t('다운로드 ${(modelProgress! * 100).toStringAsFixed(0)}%', 'Downloading ${(modelProgress! * 100).toStringAsFixed(0)}%'),
                      style:
                          Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!installed)
                        FilledButton.icon(
                          onPressed: isDownloading
                              ? null
                              : () => installLocalModel(provider),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(_t('모델 다운로드', 'Download model')),
                        ),
                      if (installed)
                        OutlinedButton.icon(
                          onPressed: isDownloading
                              ? null
                              : () => deleteLocalModel(provider),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(_t('모델 삭제', 'Remove model')),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }

          Widget diarizationPanel() {
            final downloading =
                downloadingTask == 'speaker_diarization';

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      value: diarizationEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_t('로컬 화자 구분', 'Local speaker separation')),
                      subtitle: Text(_t(
                        'STT 엔진과 별개로 녹음에서 화자를 분리해 전사 구간에 화자 1, 화자 2처럼 표시합니다.',
                        'Add labels such as Speaker 1 and Speaker 2 independently of the transcription engine.')),
                      onChanged: isDownloading
                          ? null
                          : (value) {
                              setLocalState(() {
                                diarizationEnabled = value;
                              });
                            },
                    ),
                  ),
                  Text(
                    _t('선택한 STT 엔진과 독립적으로 동작하는 별도 로컬 후처리입니다. '
                    'Groq, Cloudflare, SenseVoice, Local Whisper처럼 시간 구간이 있는 결과에 공통 적용되며 '
                    '음성은 화자 구분을 위해 외부 서버로 전송되지 않습니다.',
                    'Runs locally after transcription, with no audio upload. Works with timestamped results from Groq, Cloudflare, SenseVoice and Local Whisper.'),
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        diarizationInstalled
                            ? Icons.check_circle_outline_rounded
                            : Icons.download_for_offline_outlined,
                        size: 19,
                        color: diarizationInstalled
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          diarizationInstalled
                              ? _t('화자 구분 모델이 설치되어 있습니다.', 'Speaker models are installed.')
                              : _t('추가 로컬 모델 다운로드가 필요합니다 · 약 42MB', 'Additional local models required · about 42 MB'),
                          style:
                              Theme.of(dialogContext).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: modelProgress),
                    const SizedBox(height: 5),
                    Text(
                      modelProgress == null
                          ? _t('화자 구분 모델 다운로드 중...', 'Downloading speaker models...')
                          : _t('다운로드 ${(modelProgress! * 100).toStringAsFixed(0)}%', 'Downloading ${(modelProgress! * 100).toStringAsFixed(0)}%'),
                      style:
                          Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!diarizationInstalled)
                        OutlinedButton.icon(
                          onPressed:
                              isDownloading ? null : installDiarizationModel,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(_t('모델 다운로드', 'Download model')),
                        ),
                      if (diarizationInstalled)
                        OutlinedButton.icon(
                          onPressed:
                              isDownloading ? null : deleteDiarizationModel,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(_t('모델 삭제', 'Remove model')),
                        ),
                      SizedBox(
                        width: 190,
                        child: DropdownButtonFormField<int>(
                          initialValue: speakerCount,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: _t('화자 수', 'Speaker count'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child: Text(_t('자동 추정', 'Automatic')),
                            ),
                            ...List.generate(
                              7,
                              (index) {
                                final count = index + 2;
                                return DropdownMenuItem(
                                  value: count,
                                  child: Text(_t('$count명', '$count speakers')),
                                );
                              },
                            ),
                          ],
                          onChanged: isDownloading
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setLocalState(
                                      () => speakerCount = value,
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            insetPadding: compactSettings
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: compactSettings
                ? const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero,
                  )
                : null,
            titlePadding: compactSettings
                ? const EdgeInsets.fromLTRB(18, 18, 18, 0)
                : const EdgeInsets.fromLTRB(22, 20, 22, 0),
            contentPadding: compactSettings
                ? const EdgeInsets.fromLTRB(16, 12, 16, 8)
                : const EdgeInsets.fromLTRB(22, 14, 22, 8),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('음성 인식 설정', 'Speech recognition settings')),
                if (settingsNotice != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(settingsNotice!,
                      style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: settingsNoticeIsError ? scheme.error : scheme.primary)),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _t(
                    '녹음 속 언어와 음성을 글자로 바꾸는 방법, 화자 구분 등을 설정합니다.',
                    'Choose the recording language, how speech is converted to text, and speaker separation.',
                  ),
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                ),
              ],
            ),
            content: SizedBox(
              width: compactSettings ? dialogSize.width : 720,
              height: compactSettings ? compactContentHeight : 700,
              child: Scrollbar(
                controller: settingsScrollController,
                thumbVisibility: compactSettings,
                child: SingleChildScrollView(
                  controller: settingsScrollController,
                  primary: false,
                  // Outlined fields paint their floating label above the border.
                  padding: EdgeInsets.only(
                    top: MediaQuery.textScalerOf(dialogContext).scale(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<TranscriptionLanguage>(
                      initialValue: language,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('녹음 언어', 'Recording language'),
                        prefixIcon: const Icon(Icons.language_rounded),
                      ),
                      items: TranscriptionLanguage.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.displayLabel(useEnglish: _useEnglish)),
                            ),
                          )
                          .toList(),
                      onChanged: isDownloading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setLocalState(() {
                                language = value;
                                if (!provider.supportsLanguage(language)) {
                                  final candidates = TranscriptionProvider.values
                                      .where(
                                        (candidate) =>
                                            candidate.isLocal ==
                                                showLocalProviders &&
                                            candidate
                                                .supportsLanguage(language),
                                      )
                                      .toList();

                                  if (candidates.isNotEmpty) {
                                    provider = candidates.first;
                                  } else {
                                    provider = TranscriptionProvider.groq;
                                    showLocalProviders = false;
                                  }
                                  obscureKey = true;
                                }
                              });
                            },
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _t('자동 감지는 선택한 모델이 지원하는 언어 안에서 동작합니다. '
                          '언어를 알고 있다면 직접 선택할 수 있습니다.',
                          'Auto detection works within the selected model’s supported languages. You can also choose the spoken language explicitly.'),
                      style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t('처리 방식', 'Processing mode'),
                      style: Theme.of(dialogContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    modeSelector(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          showLocalProviders ? _t('기기 내 모델', 'Local models') : _t('온라인 서비스', 'Cloud services'),
                          style: Theme.of(dialogContext)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        _SttMiniBadge(
                          text: showLocalProviders
                              ? _t('기기 안에서 처리', 'On device')
                              : _t('인터넷으로 처리', 'Online'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...TranscriptionProvider.values
                        .where(
                          (value) => value.isLocal == showLocalProviders,
                        )
                        .map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: providerCard(value),
                          ),
                        ),
                    const SizedBox(height: 10),
                    usagePanel(),
                    const SizedBox(height: 12),
                    if (provider == TranscriptionProvider.cloudflare) ...[
                      TextField(
                        controller: cloudflareAccountController,
                        enabled: !isDownloading,
                        decoration: InputDecoration(
                          labelText: 'Cloudflare Account ID',
                          hintText: _t('Workers AI 페이지에서 확인할 수 있습니다.', 'Find it on your Workers AI page.'),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (activeKeyController != null) ...[
                      TextField(
                        key: ValueKey(provider),
                        controller: activeKeyController,
                        enabled: !isDownloading,
                        obscureText: obscureKey,
                        decoration: InputDecoration(
                          labelText: keyLabel,
                          hintText: keyHint,
                          prefixIcon: const Icon(Icons.key_outlined),
                          suffixIcon: IconButton(
                            tooltip:
                                obscureKey ? _t('API 키 표시', 'Show API key') : _t('API 키 숨기기', 'Hide API key'),
                            onPressed: () => setLocalState(
                              () => obscureKey = !obscureKey,
                            ),
                            icon: Icon(
                              obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            keyRegistered
                                ? Icons.check_circle_outline_rounded
                                : Icons.info_outline_rounded,
                            size: 17,
                            color: keyRegistered
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              keyRegistered
                                  ? _t('인증 정보가 등록되어 있습니다. 새 값을 저장하면 교체됩니다.', 'Credentials are saved. Saving a new value replaces them.')
                                  : _t('등록된 인증 정보가 없습니다.', 'No saved credentials.'),
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: keyRegistered && !isDownloading
                                ? () async {
                                    final confirmed =
                                        await showDialog<bool>(
                                      context: dialogContext,
                                      builder: (context) => AlertDialog(
                                        title:
                                            Text(_t('API 키를 삭제할까요?', 'Delete API key?')),
                                        content: Text(_t(
                                          '삭제한 키는 복구할 수 없습니다. '
                                          '필요하면 나중에 새 키를 다시 등록할 수 있습니다.',
                                          'Deleted keys cannot be recovered. You can add a new key later.')),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(_t('취소', 'Cancel')),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(_t('API 키 삭제', 'Delete API key')),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true) return;
                                    await _settings.deleteApiKey(provider);
                                    activeKeyController!.clear();
                                    setLocalState(() {
                                      hasKey[provider] = false;
                                      obscureKey = true;
                                    });
                                  }
                                : null,
                            icon:
                                const Icon(Icons.delete_outline_rounded),
                            label: Text(_t('키 삭제', 'Delete key')),
                          ),
                        ],
                      ),
                    ],
                    if (provider == TranscriptionProvider.groq) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: groqModelValue,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t('Groq Whisper 모델', 'Groq Whisper model'),
                          prefixIcon:
                              const Icon(Icons.auto_awesome_outlined),
                        ),
                        items: TranscriptionProvider.groq.models
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  TranscriptionProvider.groq
                                      .modelLabel(value, useEnglish: _useEnglish),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isDownloading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setLocalState(
                                    () => groqModelValue = value,
                                  );
                                }
                              },
                      ),
                    ],
                    if (provider == TranscriptionProvider.localWhisper) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: whisperModelValue,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t('Whisper 크기', 'Whisper size'),
                          prefixIcon: const Icon(Icons.tune_rounded),
                        ),
                        items: TranscriptionProvider.localWhisper.models
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  TranscriptionProvider.localWhisper
                                      .modelLabel(value, useEnglish: _useEnglish),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isDownloading
                            ? null
                            : (value) async {
                                if (value == null) return;
                                _whisperModelManager.size =
                                    WhisperModelSize.fromModelId(value);
                                final installed =
                                    await _whisperModelManager.isInstalled();
                                if (!dialogContext.mounted) return;
                                setLocalState(() {
                                  whisperModelValue = value;
                                  whisperInstalled = installed;
                                });
                              },
                      ),
                    ],
                    if (provider.isLocal) ...[
                      const SizedBox(height: 10),
                      localModelPanel(),
                    ],
                    const SizedBox(height: 14),
                    diarizationPanel(),
                    const SizedBox(height: 12),
                    Text(
                      provider.isLocal
                          ? _t('로컬 전사는 원본 WAV를 기기 안에서 처리합니다.', 'Local transcription processes the original WAV on your device.')
                          : _t('클라우드 전사는 전사 버튼을 누른 경우에만 녹음 파일을 선택한 서비스로 전송합니다. '
                              '인증 정보는 OS 보안 저장소에 저장됩니다.',
                              'Cloud transcription uploads audio only when you start it. Credentials are stored in OS secure storage.'),
                      style:
                          Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                    ),
                  ],
                ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDownloading
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(_t('취소', 'Cancel')),
              ),
              FilledButton(
                onPressed: isDownloading
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(_t('설정 저장', 'Save settings')),
              ),
            ],
          );
        },
      ),
    );

    settingsScrollController.dispose();
    // A cancelled dialog may have switched the manager to another size.
    await _syncWhisperSize();

    if (saved == true) {
      await _settings.setProvider(provider);
      await _settings.setTranscriptionLanguage(language);
      await _settings.setSpeakerDiarizationEnabled(diarizationEnabled);
      await _settings.setSpeakerCount(speakerCount);

      if (provider == TranscriptionProvider.groq) {
        await _settings.setModel(provider, groqModelValue);
        final key = groqController.text.trim();
        if (key.isNotEmpty) {
          await _settings.setApiKey(provider, key);
        }
      } else if (provider == TranscriptionProvider.localWhisper) {
        await _settings.setModel(provider, whisperModelValue);
      } else if (provider == TranscriptionProvider.cloudflare) {
        await _settings.setCloudflareAccountId(
          cloudflareAccountController.text,
        );
        final token = cloudflareTokenController.text.trim();
        if (token.isNotEmpty) {
          await _settings.setApiKey(provider, token);
        }
      }

      final selectedModel = switch (provider) {
        TranscriptionProvider.groq => groqModelValue,
        TranscriptionProvider.localWhisper => whisperModelValue,
        _ => provider.models.first,
      };

      if (mounted) {
        _refreshRecordingViews(() {
          _provider = provider;
          _language = language;
          _model = selectedModel;
        });
      }

      _message(
        _t('${provider.label} · ${language.label} 설정이 저장되었습니다.', '${provider.label} · ${language.displayLabel(useEnglish: true)} settings saved.'),
      );
    }

    groqController.dispose();
    cloudflareTokenController.dispose();
    cloudflareAccountController.dispose();
  }

  Future<void> _rename(RecordingItem item) async {
    var title = item.title ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('녹음 이름 변경'),
        content: TextFormField(
          initialValue: title,
          onChanged: (value) => title = value,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            hintText: '예: 주간 회의',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _recording.renameRecording(item, result);
    await _reload();
  }

  Future<void> _revealInFolder(RecordingItem item) async {
    if (!Platform.isWindows || item.audioPaths.isEmpty) {
      _message('현재는 Windows에서만 파일 위치를 바로 열 수 있습니다.');
      return;
    }

    try {
      await Process.start(
        'explorer.exe',
        ['/select,', item.audioPaths.first],
        runInShell: true,
      );
    } catch (e) {
      _message('파일 위치를 열지 못했습니다: $e', error: true);
    }
  }

  Future<void> _confirmDelete(RecordingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('휴지통으로 이동할까요?', 'Move to Trash?')),
        content: Text(
          _t(
            '“${item.displayTitle}”은(는) 휴지통으로 이동합니다. 휴지통에서 다시 복원할 수 있습니다.',
            '“${item.displayTitle}” will be moved to Trash and can be restored later.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('휴지통으로 이동', 'Move to Trash')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (_activePlayback?.id == item.id) {
      await _stopPlayback();
    }
    await _recording.moveToTrash(item);
    await _reload();
    _message(_t('휴지통으로 이동했습니다.', 'Moved to Trash.'));
  }

  Future<void> _restoreRecording(RecordingItem item) async {
    await _recording.restoreRecording(item);
    await _reload();
    _message(_t('기록을 복원했습니다.', 'Recording restored.'));
  }

  Future<void> _confirmPermanentDelete(RecordingItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('완전히 삭제할까요?', 'Delete permanently?')),
        content: Text(
          _t(
            '“${item.displayTitle}”의 원본 녹음과 전사문이 완전히 삭제됩니다. 이 작업은 되돌릴 수 없습니다.',
            'The audio and transcript for “${item.displayTitle}” will be permanently deleted. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('완전 삭제', 'Delete permanently')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (_activePlayback?.id == item.id) {
      await _stopPlayback();
    }
    await _recording.permanentlyDeleteRecording(item);
    await _reload();
    _message(_t('기록을 완전히 삭제했습니다.', 'Recording permanently deleted.'));
  }

  int _fileBytes(RecordingItem item) {
    try {
      return item.audioPaths.fold<int>(
        0,
        (sum, path) => sum + File(path).lengthSync(),
      );
    } catch (_) {
      return 0;
    }
  }

  List<RecordingItem> _scopeItems([List<RecordingItem>? source]) {
    final items = source ?? _items;

    if (_libraryScope == 'trash') {
      return items.where((item) => item.isDeleted).toList();
    }

    final active = items.where((item) => !item.isDeleted);
    if (_libraryScope == 'favorites') {
      return active.where((item) => item.isFavorite).toList();
    }
    if (_libraryScope.startsWith('collection:')) {
      final id = _libraryScope.substring('collection:'.length);
      return active.where((item) => item.collectionId == id).toList();
    }
    return active.toList();
  }

  String get _scopeTitle {
    if (_libraryScope == 'favorites') {
      return _t('즐겨찾기', 'Favorites');
    }
    if (_libraryScope == 'collections') {
      return _t('보관함', 'Collections');
    }
    if (_libraryScope == 'trash') {
      return _t('휴지통', 'Trash');
    }
    if (_libraryScope.startsWith('collection:')) {
      final id = _libraryScope.substring('collection:'.length);
      for (final collection in _collections) {
        if (collection.id == id) return collection.name;
      }
    }
    return _t('모든 기록', 'All recordings');
  }

  RecordingCollection? _collectionById(String? id) {
    if (id == null) return null;
    for (final collection in _collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  String? get _currentCollectionId =>
      _libraryScope.startsWith('collection:')
          ? _libraryScope.substring('collection:'.length)
          : null;

  int _collectionRecordingCount(String collectionId) =>
      _items
          .where((item) => !item.isDeleted && item.collectionId == collectionId)
          .length;

  void _openCollection(String collectionId) {
    if (_collectionById(collectionId) == null) return;
    _clearBatchSelection();
    setState(() {
      _libraryScope = 'collection:$collectionId';
      _workspaceView = _WorkspaceView.records;
    });
  }

  void _closeCollectionFolder() {
    _clearBatchSelection();
    setState(() {
      _libraryScope = 'collections';
    });
  }

  TranscriptSegment? _searchMatchSegment(RecordingItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final segment in item.segments) {
      if (segment.text.toLowerCase().contains(q)) return segment;
    }
    return null;
  }

  String? _searchPreview(RecordingItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final segment = _searchMatchSegment(item);
    if (segment != null) return segment.text;

    final transcript = item.transcript?.trim();
    if (transcript == null || transcript.isEmpty) return null;
    final lower = transcript.toLowerCase();
    final index = lower.indexOf(q);
    if (index < 0) return null;
    final start = (index - 40).clamp(0, transcript.length).toInt();
    final end =
        (index + q.length + 70).clamp(0, transcript.length).toInt();
    final snippet = transcript.substring(start, end).replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    return '${start > 0 ? '…' : ''}$snippet${end < transcript.length ? '…' : ''}';
  }

  List<RecordingItem> get _filteredItems {
    final scoped = _scopeItems();
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return scoped;

    return scoped.where((item) {
      final collection = _collectionById(item.collectionId);
      final haystack = [
        item.displayTitle,
        item.fileName,
        item.transcript ?? '',
        collection?.name ?? '',
        formatRecordingDate(item.createdAt),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Future<void> _pickAudioFiles() async {
    if (_isRecording || _importingFiles) return;

    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '오디오 또는 영상 파일 가져오기',
        type: FileType.custom,
        allowedExtensions: RecordingService.supportedImportExtensions,
      );
      if (files.isEmpty) return;

      final paths = files
          .map((file) => file.path)
          .whereType<String>()
          .toList();
      await _importAudioPaths(paths);
    } catch (e) {
      _message('파일 선택 창을 열지 못했습니다: $e', error: true);
    }
  }

  Future<void> _importAudioPaths(Iterable<String> paths) async {
    if (_isRecording) {
      _message('녹음을 종료한 뒤 파일을 가져와 주세요.', error: true);
      return;
    }
    if (_importingFiles) return;

    final uniquePaths = paths
        .where((path) => path.trim().isNotEmpty)
        .toSet()
        .toList();
    if (uniquePaths.isEmpty) return;

    final supported = uniquePaths
        .where(RecordingService.isSupportedImportPath)
        .toList();
    final skipped = uniquePaths.length - supported.length;

    if (supported.isEmpty) {
      _message(
        '가져올 수 있는 파일이 없습니다. WAV, M4A, MP3, MP4, WebM을 지원합니다.',
        error: true,
      );
      return;
    }

    if (mounted) {
      setState(() => _importingFiles = true);
    }

    var imported = 0;
    String? firstImportedId;
    final failures = <String>[];
    var hasNonWav = false;

    try {
      for (final path in supported) {
        try {
          final item = await _recording.importAudioFile(path);
          imported += 1;
          firstImportedId ??= item.id;
          if (!path.toLowerCase().endsWith('.wav')) {
            hasNonWav = true;
          }
        } catch (e) {
          failures.add(File(path).uri.pathSegments.last);
        }
      }

      await _reload();
      if (mounted && firstImportedId != null) {
        setState(() => _selectedRecordingId = firstImportedId);
      }

      if (imported > 0) {
        final cloudNote = hasNonWav
            ? ' WAV 외 형식은 현재 클라우드 전사를 사용해 주세요.'
            : '';
        final skippedNote =
            skipped > 0 ? ' 지원하지 않는 파일 $skipped개는 건너뛰었습니다.' : '';
        final failureNote = failures.isNotEmpty
            ? ' 가져오지 못한 파일 ${failures.length}개가 있습니다.'
            : '';
        _message(
          '$imported개 파일을 가져왔습니다.$cloudNote$skippedNote$failureNote',
        );
      } else {
        _message('파일을 가져오지 못했습니다.', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _importingFiles = false);
      }
    }
  }

  Future<void> _editTranscript(RecordingItem item) async {
    final result = await TranscriptEditorDialog.show(
      context,
      item: item,
      useEnglish: _useEnglish,
    );
    if (result == null) return;

    try {
      await _recording.updateTranscript(
        item,
        text: result.text,
        segments: result.segments,
        speakerLabels: result.speakerLabels,
      );
      await _reload();
      _expandedTranscripts.add(item.id);
      _message(_t('전사문을 저장했습니다.', 'Transcript saved.'));
    } catch (e) {
      _message(
        _t('전사문을 저장하지 못했습니다: $e', 'Could not save transcript: $e'),
        error: true,
      );
    }
  }

  Future<void> _exportTranscript(
    RecordingItem item,
    TranscriptExportFormat format,
  ) async {
    try {
      final saved = await _transcriptExport.save(item, format);
      if (saved) {
        _message('${format.label} 파일로 내보냈습니다.');
      }
    } catch (e) {
      _message('전사문을 내보내지 못했습니다: $e', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = _settingsMessengerKey.currentState ??
        _detailMessengerKey.currentState ?? ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text.replaceFirst('Exception: ', '')),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _createCollection() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('새 보관함', 'New collection')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: _t('예: 면접, 회의, 강의', 'e.g. Interviews, Meetings'),
            prefixIcon: const Icon(Icons.folder_outlined),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_t('만들기', 'Create')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;

    try {
      final collection = await _recording.createCollection(name);
      await _reload();
      if (!mounted) return;
      setState(() => _libraryScope = 'collection:${collection.id}');
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  Future<void> _renameCollection(RecordingCollection collection) async {
    final controller = TextEditingController(text: collection.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('보관함 이름 변경', 'Rename collection')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(_t('저장', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _recording.renameCollection(collection.id, name);
    await _reload();
  }

  Future<void> _deleteCollection(RecordingCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('보관함을 삭제할까요?', 'Delete collection?')),
        content: Text(
          _t(
            '보관함만 삭제되고 안에 있는 녹음은 “모든 기록”에 그대로 남습니다.',
            'Only the collection is removed. Its recordings remain in All recordings.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('보관함 삭제', 'Delete collection')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _recording.deleteCollection(collection.id);
    if (!mounted) return;
    setState(() {
      _libraryScope = 'collections';
    });
    await _reload();
  }

  Future<String?> _chooseCollection({
    String? currentId,
    bool allowUnfiled = true,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowUnfiled)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text(_t('보관함 없음', 'No collection')),
                  trailing: currentId == null
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, '__none__'),
                ),
              ..._collections.map(
                (collection) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(collection.name),
                  trailing: collection.id == currentId
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, collection.id),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(_t('새 보관함 만들기', 'Create new collection')),
                onTap: () {
                  Navigator.pop(sheetContext, '__create__');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _moveItemsToCollection(List<RecordingItem> items) async {
    if (items.isEmpty) return;
    var selected = await _chooseCollection(
      currentId: items.length == 1 ? items.first.collectionId : null,
    );
    if (selected == null) return;

    if (selected == '__create__') {
      await _createCollection();
      if (!mounted || !_libraryScope.startsWith('collection:')) return;
      selected = _libraryScope.substring('collection:'.length);
    }

    final collectionId = selected == '__none__' ? null : selected;
    for (final item in items) {
      await _recording.setCollection(item, collectionId);
    }
    if (_selectionMode) {
      _clearBatchSelection();
    }
    await _reload();
    _message(
      collectionId == null
          ? _t('보관함에서 꺼냈습니다.', 'Removed from collection.')
          : _t('보관함으로 이동했습니다.', 'Moved to collection.'),
    );
  }

  Future<void> _toggleFavorite(RecordingItem item) async {
    await _recording.setFavorite(item, !item.isFavorite);
    await _reload();
  }

  List<RecordingItem> get _batchSelectedItems => _items
      .where((item) => _batchSelectedIds.contains(item.id))
      .toList();

  void _toggleBatchSelection(RecordingItem item) {
    setState(() {
      _selectionMode = true;
      if (!_batchSelectedIds.add(item.id)) {
        _batchSelectedIds.remove(item.id);
      }
      if (_batchSelectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _setBatchSelection(Set<String> ids) {
    setState(() {
      _selectionMode = true;
      _batchSelectedIds..clear()..addAll(ids);
    });
  }

  void _selectAllVisible() {
    final ids = _filteredItems.map((item) => item.id).toSet();
    _setBatchSelection(ids.every(_batchSelectedIds.contains) ? {} : ids);
  }

  void _clearBatchSelection() {
    setState(() {
      _selectionMode = false;
      _batchSelectedIds.clear();
    });
  }

  Future<void> _batchTranscribeSelected() async {
    if (_batchTranscriptionRunning) return;
    final items = _batchSelectedItems
        .where((item) => !item.isDeleted)
        .toList(growable: false);
    if (items.isEmpty) return;

    setState(() {
      _batchTranscriptionRunning = true;
      _batchTranscriptionCompleted = 0;
      _batchTranscriptionTotal = items.length;
    });

    try {
      for (var index = 0; index < items.length; index++) {
        if (!mounted) return;
        await _transcribe(items[index], announceCompletion: false);
        if (!mounted) return;
        setState(() => _batchTranscriptionCompleted = index + 1);
      }
      _message(
        _t(
          '${items.length}개 기록의 전사 대기열 처리가 끝났습니다.',
          'Finished the transcription queue for ${items.length} recordings.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _batchTranscriptionRunning = false;
          _batchTranscriptionCompleted = 0;
          _batchTranscriptionTotal = 0;
        });
        _clearBatchSelection();
      }
    }
  }

  Future<void> _batchFavorite(bool value) async {
    final items = _batchSelectedItems;
    for (final item in items) {
      await _recording.setFavorite(item, value);
    }
    _clearBatchSelection();
    await _reload();
  }

  Future<void> _batchTrash() async {
    final items = _batchSelectedItems;
    for (final item in items) {
      if (!item.isDeleted) {
        await _recording.moveToTrash(item);
      }
    }
    _clearBatchSelection();
    await _reload();
  }

  Future<void> _batchRestore() async {
    final items = _batchSelectedItems;
    for (final item in items) {
      if (item.isDeleted) {
        await _recording.restoreRecording(item);
      }
    }
    _clearBatchSelection();
    await _reload();
  }

  Future<void> _batchPermanentDelete() async {
    final items = _batchSelectedItems.where((item) => item.isDeleted).toList();
    if (items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('선택한 기록을 완전히 삭제할까요?', 'Delete selected recordings permanently?')),
        content: Text(
          _t(
            '${items.length}개의 원본 녹음과 전사문이 완전히 삭제됩니다. 이 작업은 되돌릴 수 없습니다.',
            '${items.length} recordings and their transcripts will be permanently deleted. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('취소', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('완전 삭제', 'Delete permanently')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final item in items) {
      await _recording.permanentlyDeleteRecording(item);
    }
    _clearBatchSelection();
    await _reload();
  }

  Future<void> _jumpToSearchMatch(RecordingItem item) async {
    final segment = _searchMatchSegment(item);
    if (segment == null) return;
    setState(() {
      _selectedRecordingId = item.id;
      _workspaceView = _WorkspaceView.records;
    });
    await _playFrom(
      item,
      Duration(milliseconds: (segment.startSeconds * 1000).round()),
    );
  }

  Widget _buildBrand({double iconSize = 34, bool showName = true}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(iconSize * 0.28),
          child: Image.asset(
            'assets/spokenlog_icon.png',
            width: iconSize,
            height: iconSize,
            fit: BoxFit.cover,
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 9),
          Text(
            'SpokenLog',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.45,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildEngineBadge({
    bool wide = false,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final model = _provider.modelLabel(_model).split(' · ').first;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap ?? () => unawaited(_showQuickTranscriptionPanel()),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: wide ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _provider.isLocal
                      ? Icons.computer_rounded
                      : Icons.cloud_queue_rounded,
                  size: 17,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 9),
              if (wide)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_t(_provider.categoryLabel, _provider.isLocal ? 'Local' : 'Cloud')} · ${_provider.shortLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$model · ${_language.displayLabel(useEnglish: _useEnglish)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_t(_provider.categoryLabel, _provider.isLocal ? 'Local' : 'Cloud')} · ${_provider.shortLabel}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      '$model · ${_language.displayLabel(useEnglish: _useEnglish)}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 920) {
          return const SizedBox.shrink();
        }

        final compact = constraints.maxWidth < 600;

        return Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            10,
            compact ? 12 : 16,
            11,
          ),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Align(alignment: Alignment.centerLeft,
                    child: FittedBox(fit: BoxFit.scaleDown,
                      child: _buildBrand(iconSize: 34)))),
                  IconButton.filledTonal(
                    tooltip: _t('설정', 'Settings'),
                    onPressed: () => unawaited(_showAppSettings()),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              _buildEngineBadge(wide: true),
              const SizedBox(height: 9),
              if (_isRecording)
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (_isPausedRecording
                                ? _t('일시정지', 'Paused')
                                : _t('녹음 중', 'Recording')) +
                            ' · ' +
                            formatDuration(_liveRecordingDuration),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: _isPausedRecording
                          ? _t('계속 녹음', 'Resume recording')
                          : _t('일시정지', 'Pause'),
                      onPressed: _toggleRecordingPause,
                      icon: Icon(
                        _isPausedRecording
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                      ),
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop_rounded, size: 18),
                      label: Text(_t('종료', 'Stop')),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importingFiles ? null : _pickAudioFiles,
                        icon: _importingFiles
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file_rounded, size: 19),
                        label: Text(
                          _importingFiles
                              ? _t('가져오는 중', 'Importing')
                              : _t('파일 가져오기', 'Import file'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _startRecording,
                        icon: const Icon(Icons.mic_none_rounded, size: 19),
                        label: Text(_t('새 녹음', 'New recording')),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarHeader() {
    final scheme = Theme.of(context).colorScheme;
    final scoped = _scopeItems();
    final transcriptCount = scoped.where((item) => item.hasTranscript).length;
    final scopedDuration = Duration(
      milliseconds: scoped.fold<int>(
        0,
        (sum, item) => sum + item.durationMs,
      ),
    );
    final selectedCount = _batchSelectedIds.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _scopeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              if (!_selectionMode && scoped.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selectionMode = true),
                  child: Text(_t('선택', 'Select')),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  scoped.length.toString(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          if (_selectionMode) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_t('$selectedCount개 선택', '$selectedCount selected'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
                  TextButton(
                    key: const ValueKey('select-all-visible'),
                    onPressed: _selectAllVisible,
                    child: Text(_filteredItems.isNotEmpty &&
                        _filteredItems.every((item) => _batchSelectedIds.contains(item.id))
                        ? _t('전체 해제', 'Deselect all') : _t('전체 선택', 'Select all')),
                  ),
                  if (_libraryScope == 'trash') ...[
                    IconButton(
                      tooltip: _t('복원', 'Restore'),
                      onPressed:
                          selectedCount == 0 ? null : () => unawaited(_batchRestore()),
                      icon: const Icon(Icons.restore_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: _t('완전 삭제', 'Delete permanently'),
                      onPressed: selectedCount == 0
                          ? null
                          : () => unawaited(_batchPermanentDelete()),
                      icon: Icon(
                        Icons.delete_forever_rounded,
                        size: 20,
                        color: scheme.error,
                      ),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: _batchTranscriptionRunning
                          ? _t(
                              '전사 대기열 $_batchTranscriptionCompleted/$_batchTranscriptionTotal',
                              'Transcription queue $_batchTranscriptionCompleted/$_batchTranscriptionTotal',
                            )
                          : _t('선택한 기록 전사', 'Transcribe selected'),
                      onPressed: selectedCount == 0 || _batchTranscriptionRunning
                          ? null
                          : () => unawaited(_batchTranscribeSelected()),
                      icon: _batchTranscriptionRunning
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: _t('보관함으로 이동', 'Move to collection'),
                      onPressed: selectedCount == 0
                          ? null
                          : () => unawaited(
                                _moveItemsToCollection(_batchSelectedItems),
                              ),
                      icon: const Icon(Icons.drive_file_move_outline, size: 20),
                    ),
                    IconButton(
                      tooltip: _libraryScope == 'favorites'
                          ? _t('즐겨찾기 해제', 'Remove from favorites')
                          : _t('즐겨찾기', 'Favorite'),
                      onPressed: selectedCount == 0
                          ? null
                          : () => unawaited(
                                _batchFavorite(_libraryScope != 'favorites'),
                              ),
                      icon: Icon(
                        _libraryScope == 'favorites'
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('휴지통으로 이동', 'Move to Trash'),
                      onPressed: selectedCount == 0
                          ? null
                          : () => unawaited(_batchTrash()),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    ),
                  ],
                  IconButton(
                    tooltip: _t('선택 취소', 'Cancel selection'),
                    onPressed: _clearBatchSelection,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
          if (!_selectionMode && scoped.isNotEmpty)
            Text(_t('길게 누른 뒤 끌어서 여러 개 선택', 'Hold and drag to select multiple'),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 11),
          SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _query = value;
                _batchSelectedIds.clear();
              }),
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: _t('제목이나 전사 내용 검색…', 'Search titles or transcripts…'),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: _t('검색 지우기', 'Clear search'),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            _useEnglish
                ? 'Total ${formatDuration(scopedDuration)} · $transcriptCount transcribed'
                : '총 ${formatDuration(scopedDuration)} · 전사 $transcriptCount개',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(
    RecordingItem item, {
    required double progress,
  }) {
    final scheme = Theme.of(context).colorScheme;

    if (item.audioPaths.isEmpty) return const SizedBox.shrink();

    final future = _waveformFutures.putIfAbsent(
      item.id,
      () => _waveformService.readPeaks(item.audioPaths.first),
    );

    return FutureBuilder<List<double>>(
      future: future,
      builder: (context, snapshot) {
        final peaks = snapshot.data ?? const <double>[];

        if (peaks.isEmpty) {
          return const SizedBox(height: 4);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _isRecording
                  ? null
                  : (details) {
                      final width = constraints.maxWidth;
                      if (width <= 0 || item.durationMs <= 0) return;

                      final ratio =
                          (details.localPosition.dx / width).clamp(0.0, 1.0);
                      final target = Duration(
                        milliseconds: (item.durationMs * ratio).round(),
                      );
                      unawaited(
                        _seekPlayback(item, target, forcePlay: true),
                      );
                    },
              child: CustomPaint(
                size: const Size(double.infinity, 58),
                painter: _WaveformPainter(
                  peaks: peaks,
                  progress: progress,
                  activeColor: scheme.primary,
                  inactiveColor: scheme.outlineVariant,
                  centerLineColor:
                      scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaybackControls(RecordingItem item) {
    final scheme = Theme.of(context).colorScheme;
    final active = _activePlayback?.id == item.id;
    final total = active && _playbackTotal > Duration.zero
        ? _playbackTotal
        : item.duration;
    final shownPosition = active
        ? (_draggingPlayback ? _dragPosition : _playbackPosition)
        : Duration.zero;
    final totalMs = total.inMilliseconds;
    final ratio = totalMs > 0
        ? (shownPosition.inMilliseconds / totalMs)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;

    Widget positionSlider() {
      return Slider(
        key: ValueKey('playback-slider-${item.id}'),
        value: ratio,
        onChangeStart: active && totalMs > 0 && !_isRecording
            ? (value) {
                _refreshRecordingViews(() {
                  _draggingPlayback = true;
                  _dragPosition = Duration(
                    milliseconds: (totalMs * value).round(),
                  );
                });
              }
            : null,
        onChanged: active && totalMs > 0 && !_isRecording
            ? (value) {
                _refreshRecordingViews(() {
                  _dragPosition = Duration(
                    milliseconds: (totalMs * value).round(),
                  );
                });
              }
            : null,
        onChangeEnd: active && totalMs > 0 && !_isRecording
            ? (value) {
                final target = Duration(
                  milliseconds: (totalMs * value).round(),
                );
                unawaited(_seekPlayback(item, target));
              }
            : null,
      );
    }

    Widget ratePicker() {
      return DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          value: _playbackRate,
          borderRadius: BorderRadius.circular(8),
          items: const [
            DropdownMenuItem(value: 0.75, child: Text('0.75×')),
            DropdownMenuItem(value: 1.0, child: Text('1×')),
            DropdownMenuItem(value: 1.25, child: Text('1.25×')),
            DropdownMenuItem(value: 1.5, child: Text('1.5×')),
            DropdownMenuItem(value: 2.0, child: Text('2×')),
          ],
          onChanged: _isRecording
              ? null
              : (value) {
                  if (value != null) {
                    unawaited(_setPlaybackRate(value));
                  }
                },
        ),
      );
    }

    Text timeText(Duration value, {bool secondary = false}) {
      return Text(
        formatDuration(value),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: secondary ? scheme.onSurfaceVariant : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;

        return Container(
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 12,
            10,
            compact ? 10 : 12,
            compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              _buildWaveform(item, progress: ratio),
              if (item.audioPaths.isNotEmpty) const SizedBox(height: 4),
              if (compact) ...[
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    IconButton.filled(
                      tooltip:
                          active && _isPlayingAudio ? '일시정지' : '재생',
                      onPressed:
                          _isRecording ? null : () => _togglePlayback(item),
                      icon: Icon(
                        active && _isPlayingAudio
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    timeText(shownPosition),
                    const SizedBox(width: 6),
                    Text(
                      '/',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
                          ),
                    ),
                    const SizedBox(width: 6),
                    totalMs > 0
                        ? timeText(total, secondary: true)
                        : Text(
                            '--:--',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                    ratePicker(),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: positionSlider(),
                ),
              ] else
                Row(
                  children: [
                    IconButton.filled(
                      tooltip:
                          active && _isPlayingAudio ? '일시정지' : '재생',
                      onPressed:
                          _isRecording ? null : () => _togglePlayback(item),
                      icon: Icon(
                        active && _isPlayingAudio
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    timeText(shownPosition),
                    const SizedBox(width: 10),
                    Expanded(child: positionSlider()),
                    const SizedBox(width: 10),
                    totalMs > 0
                        ? timeText(total, secondary: true)
                        : Text(
                            '--:--',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                    const SizedBox(width: 12),
                    ratePicker(),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTranscript(RecordingItem item) {
    final scheme = Theme.of(context).colorScheme;

    if (!item.hasTranscript) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notes_outlined,
              size: 30,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              _t('아직 전사문이 없습니다.', 'No transcript yet.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              _t('전사를 실행하면 이 영역에서 시간대별 내용을 확인할 수 있습니다.', 'Run transcription to see timestamped text here.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    if (item.segments.isNotEmpty) {
      return Container(
        height: 390,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: item.segments.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: scheme.outlineVariant,
          ),
          itemBuilder: (context, index) {
            final segment = item.segments[index];

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _seekPlayback(
                  item,
                  Duration(
                    milliseconds: (segment.startSeconds * 1000).round(),
                  ),
                  forcePlay: true,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 88,
                        child: Text(
                          '${formatTimestamp(segment.startSeconds)}–'
                          '${formatTimestamp(segment.endSeconds)}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (segment.speaker != null) ...[
                        Container(
                          constraints: const BoxConstraints(minWidth: 54),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.speakerLabel(segment.speaker!),
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                        const SizedBox(width: 9),
                      ],
                      Expanded(
                        child: Text(
                          segment.text,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Container(
      height: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          item.transcript!,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildRecordingCard(RecordingItem item) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _transcribing.contains(item.id) ||
        _pendingTranscription.contains(item.id);
    final active = _activePlayback?.id == item.id;
    final durationText =
        item.durationMs > 0 ? formatDuration(item.duration) : _t('길이 확인 중', 'Checking duration');
    final bytes = _fileBytes(item);

    Widget titleBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            '${formatRecordingDate(item.createdAt)} · '
            '$durationText · ${formatFileSize(bytes)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    Widget compactMoreMenu() {
      return PopupMenuButton<String>(
        tooltip: _t('기록 메뉴', 'Recording menu'),
        onSelected: (value) {
          switch (value) {
            case 'rename':
              unawaited(_rename(item));
            case 'favorite':
              unawaited(_toggleFavorite(item));
            case 'collection':
              unawaited(_moveItemsToCollection([item]));
            case 'reveal':
              unawaited(_revealInFolder(item));
            case 'delete':
              unawaited(_confirmDelete(item));
            case 'restore':
              unawaited(_restoreRecording(item));
            case 'delete_permanently':
              unawaited(_confirmPermanentDelete(item));
          }
        },
        itemBuilder: (_) => item.isDeleted
            ? [
                PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      const Icon(Icons.restore_rounded, size: 19),
                      const SizedBox(width: 10),
                      Text(_t('복원', 'Restore')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete_permanently',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_forever_rounded, size: 19),
                      const SizedBox(width: 10),
                      Text(_t('완전 삭제', 'Delete permanently')),
                    ],
                  ),
                ),
              ]
            : [
                PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 19),
                      const SizedBox(width: 10),
                      Text(_t('이름 변경', 'Rename')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Row(
                    children: [
                      Icon(
                        item.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        item.isFavorite
                            ? _t('즐겨찾기 해제', 'Remove from favorites')
                            : _t('즐겨찾기', 'Add to favorites'),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'collection',
                  child: Row(
                    children: [
                      const Icon(Icons.drive_file_move_outline, size: 19),
                      const SizedBox(width: 10),
                      Text(_t('보관함으로 이동', 'Move to collection')),
                    ],
                  ),
                ),
                if (Platform.isWindows)
                  PopupMenuItem(
                    value: 'reveal',
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open_outlined, size: 19),
                        const SizedBox(width: 10),
                        Text(_t('파일 위치 열기', 'Show in folder')),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, size: 19),
                      const SizedBox(width: 10),
                      Text(_t('휴지통으로 이동', 'Move to Trash')),
                    ],
                  ),
                ),
              ],
      );
    }

    Widget desktopManagementActions() {
      if (item.isDeleted) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _t('복원', 'Restore'),
              onPressed: () => unawaited(_restoreRecording(item)),
              icon: const Icon(Icons.restore_rounded, size: 20),
            ),
            IconButton(
              tooltip: _t('완전 삭제', 'Delete permanently'),
              onPressed: () => unawaited(_confirmPermanentDelete(item)),
              icon: Icon(
                Icons.delete_forever_rounded,
                size: 20,
                color: scheme.error,
              ),
            ),
          ],
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: item.isFavorite
                ? _t('즐겨찾기 해제', 'Remove from favorites')
                : _t('즐겨찾기', 'Add to favorites'),
            onPressed: () => unawaited(_toggleFavorite(item)),
            icon: Icon(
              item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 20,
              color: item.isFavorite ? scheme.primary : null,
            ),
          ),
          IconButton(
            tooltip: _t('보관함으로 이동', 'Move to collection'),
            onPressed: () => unawaited(_moveItemsToCollection([item])),
            icon: const Icon(Icons.drive_file_move_outline, size: 20),
          ),
          IconButton(
            tooltip: _t('이름 변경', 'Rename'),
            onPressed: () => _rename(item),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          if (Platform.isWindows)
            IconButton(
              tooltip: _t('파일 위치 열기', 'Show in folder'),
              onPressed: () => _revealInFolder(item),
              icon: const Icon(Icons.folder_open_outlined, size: 20),
            ),
          PopupMenuButton<String>(
            tooltip: _t('더보기', 'More'),
            onSelected: (value) {
              if (value == 'delete') {
                unawaited(_confirmDelete(item));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, size: 19),
                    const SizedBox(width: 10),
                    Text(_t('휴지통으로 이동', 'Move to Trash')),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    Widget exportButton() {
      return PopupMenuButton<TranscriptExportFormat>(
        tooltip: _t('전사문 내보내기', 'Export transcript'),
        onSelected: (format) {
          unawaited(_exportTranscript(item, format));
        },
        itemBuilder: (context) => TranscriptExportFormat.values
            .map(
              (format) => PopupMenuItem(
                value: format,
                child: Row(
                  children: [
                    const Icon(Icons.download_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text('${format.label} (.${format.extension})'),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_outlined, size: 17),
              const SizedBox(width: 7),
              Text(_t('내보내기', 'Export')),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_drop_down_rounded, size: 18),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        return Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(14, 14, 14, 22)
              : const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                titleBlock(),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerRight,
                  child: compactMoreMenu(),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleBlock()),
                    desktopManagementActions(),
                  ],
                ),
              const SizedBox(height: 12),
              _buildPlaybackControls(item),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: ValueKey('transcribe-${item.id}'),
                    onPressed: busy ? null : () => _transcribe(item),
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(
                      busy
                          ? _transcribingProgress[item.id] ?? '전사 중'
                          : item.hasTranscript
                              ? _t('다시 전사', 'Transcribe again')
                              : _provider.shortLabel + _t('로 전사', ' transcription'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => unawaited(_openSettings()),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: Text(_t('전사 설정', 'Transcription settings')),
                  ),
                  if (item.hasTranscript)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_editTranscript(item)),
                      icon: const Icon(Icons.edit_note_rounded, size: 18),
                      label: Text(_t('수정', 'Edit')),
                    ),
                  if (item.hasTranscript)
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: item.transcript!),
                        );
                        _message(_t('전사문을 복사했습니다.', 'Transcript copied.'));
                      },
                      icon: const Icon(Icons.copy_outlined, size: 17),
                      label: Text(_t('복사', 'Copy')),
                    ),
                  if (item.hasTranscript) exportButton(),
                  if (active && _isPlayingAudio)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        _t('$_playbackRate× 재생 중', 'Playing at $_playbackRate×'),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _t('전사문', 'Transcript'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (item.segments.isNotEmpty)
                    Text(
                      _t('${item.segments.length}개 구간', item.segments.length == 1 ? '1 segment' : '${item.segments.length} segments'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  if (item.segments.isNotEmpty)
                    Text(
                      _t('시간을 누르면 해당 위치에서 재생됩니다.', 'Click a timestamp to play from that point.'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildTranscript(item),
            ],
          ),
        );
      },
    );
  }

  RecordingItem? _selectedFrom(List<RecordingItem> items) {
    if (items.isEmpty) return null;
    final selectedId = _selectedRecordingId;
    if (selectedId == null) return items.first;

    for (final item in items) {
      if (item.id == selectedId) return item;
    }
    return items.first;
  }

  Widget _buildCompactRecordingTile(
    RecordingItem item, {
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool dragSelection = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedRecordingId == item.id;
    final selectedForBatch = _batchSelectedIds.contains(item.id);
    final playing = _activePlayback?.id == item.id && _isPlayingAudio;
    final duration =
        item.durationMs > 0 ? formatDuration(item.duration) : '--:--';
    final collection = _collectionById(item.collectionId);
    final searchPreview = _searchPreview(item);
    final matchSegment = _searchMatchSegment(item);

    void handleTap() {
      if (_selectionMode) {
        _toggleBatchSelection(item);
      } else {
        onTap();
      }
    }

    void handleLongPress() {
      if (_selectionMode) {
        _toggleBatchSelection(item);
        return;
      }
      if (onLongPress != null) {
        onLongPress();
      } else {
        unawaited(_showRecordingActions(item));
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
      child: Material(
        color: selectedForBatch
            ? scheme.primaryContainer
            : selected
                ? scheme.primaryContainer.withValues(alpha: 0.52)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: handleTap,
          onLongPress: dragSelection ? null : handleLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: BoxConstraints(
              minHeight: searchPreview == null ? 68 : 92,
            ),
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selectedForBatch || selected
                    ? scheme.primary.withValues(alpha: 0.42)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_selectionMode)
                  Checkbox(
                    value: selectedForBatch,
                    onChanged: (_) => _toggleBatchSelection(item),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  IconButton(
                    tooltip: playing
                        ? _t('일시정지', 'Pause')
                        : _t('재생', 'Play'),
                    onPressed:
                        _isRecording || item.isDeleted ? null : () => _togglePlayback(item),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      item.isDeleted
                          ? Icons.delete_outline_rounded
                          : playing
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_outline_rounded,
                      size: 27,
                      color: selected || playing
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: selected || selectedForBatch
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ),
                          if (item.isFavorite && !item.isDeleted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          formatRecordingDate(item.createdAt),
                          if (collection != null) collection.name,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      if (searchPreview != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                searchPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.25,
                                    ),
                              ),
                            ),
                            if (matchSegment != null && !item.isDeleted)
                              IconButton(
                                tooltip: _t(
                                  '검색된 부분부터 재생',
                                  'Play from match',
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    unawaited(_jumpToSearchMatch(item)),
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      duration,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    if (dragSelection && !_selectionMode)
                      IconButton(
                        tooltip: _t('기록 메뉴', 'Recording menu'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => unawaited(_showRecordingActions(item)),
                        icon: const Icon(Icons.more_horiz, size: 18),
                      )
                    else Icon(
                      item.isDeleted
                          ? Icons.restore_from_trash_outlined
                          : item.hasTranscript
                              ? Icons.check_circle_rounded
                              : Icons.horizontal_rule_rounded,
                      size: 15,
                      color: item.hasTranscript
                          ? scheme.primary
                          : scheme.outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRecordingDetails(RecordingItem item) async {
    setState(() => _selectedRecordingId = item.id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.9,
        child: RecordingDetailsSheet(
          changes: _recordingDetailChanges,
          messengerKey: _detailMessengerKey,
          useEnglish: _useEnglish,
          builder: (_) {
            if (!mounted || !_viewActive) return const SizedBox.shrink();
            final latest = _items.where((entry) => entry.id == item.id);
            if (latest.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_t('이 녹음은 삭제되었습니다.', 'This recording was deleted.')),
              );
            }
            return _buildRecordingCard(latest.first);
          },
        ),
      ),
    );
  }

  Widget _buildDesktopNavigation() {
    final scheme = Theme.of(context).colorScheme;
    final activeCount = _items.where((item) => !item.isDeleted).length;
    final favoriteCount =
        _items.where((item) => !item.isDeleted && item.isFavorite).length;
    final trashCount = _items.where((item) => item.isDeleted).length;

    Widget navItem({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      String? count,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: selected
              ? scheme.surfaceContainerHigh
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      count,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrand(iconSize: 38),
          const SizedBox(height: 23),
          if (_isRecording) ...[
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t(
                      '녹음 중 · ' + formatDuration(_liveRecordingDuration),
                      'Recording · ' + formatDuration(_liveRecordingDuration),
                    ),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _toggleRecordingPause,
                          child: Text(
                            _isPausedRecording
                                ? _t('계속', 'Resume')
                                : _t('일시정지', 'Pause'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: _t('녹음 종료', 'Stop recording'),
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
              ),
              onPressed: _startRecording,
              icon: const Icon(Icons.mic_none_rounded, size: 20),
              label: Text(_t('새 녹음', 'New recording')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(43),
              ),
              onPressed: _importingFiles ? null : _pickAudioFiles,
              icon: const Icon(Icons.upload_file_rounded, size: 19),
              label: Text(
                _importingFiles
                    ? _t('가져오는 중', 'Importing')
                    : _t('파일 가져오기', 'Import file'),
              ),
            ),
          ],
          const SizedBox(height: 22),
          navItem(
            icon: Icons.folder_open_rounded,
            label: _t('모든 기록', 'All recordings'),
            selected: _workspaceView == _WorkspaceView.records &&
                _libraryScope == 'all',
            count: activeCount.toString(),
            onTap: () {
              _clearBatchSelection();
              setState(() {
                _libraryScope = 'all';
                _workspaceView = _WorkspaceView.records;
              });
            },
          ),
          navItem(
            icon: Icons.calendar_month_rounded,
            label: _t('캘린더', 'Calendar'),
            selected: _workspaceView == _WorkspaceView.calendar,
            onTap: () {
              _clearBatchSelection();
              setState(() {
                if (_libraryScope == 'trash') _libraryScope = 'all';
                _workspaceView = _WorkspaceView.calendar;
              });
            },
          ),
          navItem(
            icon: Icons.star_outline_rounded,
            label: _t('즐겨찾기', 'Favorites'),
            selected: _workspaceView == _WorkspaceView.records &&
                _libraryScope == 'favorites',
            count: favoriteCount.toString(),
            onTap: () {
              _clearBatchSelection();
              setState(() {
                _libraryScope = 'favorites';
                _workspaceView = _WorkspaceView.records;
              });
            },
          ),
          navItem(
            icon: Icons.delete_outline_rounded,
            label: _t('휴지통', 'Trash'),
            selected: _workspaceView == _WorkspaceView.records &&
                _libraryScope == 'trash',
            count: trashCount.toString(),
            onTap: () {
              _clearBatchSelection();
              setState(() {
                _libraryScope = 'trash';
                _workspaceView = _WorkspaceView.records;
              });
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('보관함', 'Collections'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              IconButton(
                tooltip: _t('새 보관함', 'New collection'),
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_createCollection()),
                icon: const Icon(Icons.add_rounded, size: 19),
              ),
            ],
          ),
          ..._collections.map(
            (collection) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: _libraryScope == 'collection:${collection.id}' &&
                        _workspaceView == _WorkspaceView.records
                    ? scheme.surfaceContainerHigh
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _clearBatchSelection();
                    setState(() {
                      _libraryScope = 'collection:${collection.id}';
                      _workspaceView = _WorkspaceView.records;
                    });
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 19,
                          color: _libraryScope ==
                                  'collection:${collection.id}'
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            collection.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: _t('보관함 메뉴', 'Collection menu'),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            if (value == 'rename') {
                              unawaited(_renameCollection(collection));
                            } else if (value == 'delete') {
                              unawaited(_deleteCollection(collection));
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text(_t('이름 변경', 'Rename')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(_t('보관함 삭제', 'Delete collection')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 5),
          navItem(
            icon: Icons.settings_outlined,
            label: _t('설정', 'Settings'),
            selected: false,
            onTap: () => unawaited(_showAppSettings()),
          ),
          const Spacer(),
          Text(
            _t('현재 음성 인식', 'Current speech recognition'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 7),
          _buildEngineBadge(
            wide: true,
            onTap: () => unawaited(_showEnginePanel()),
          ),
          const SizedBox(height: 10),
          Text(
            'AGPL-3.0 · Local-first',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  String _recordingPreview(RecordingItem item) {
    final transcript = item.transcript?.trim();
    if (transcript == null || transcript.isEmpty) {
      return _t('아직 전사하지 않은 녹음입니다.', 'Not transcribed yet.');
    }
    final normalized = transcript.replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length > 100
        ? normalized.substring(0, 100) + '…'
        : normalized;
  }

  Future<void> _showRecordingActions(RecordingItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!item.isDeleted) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(_t('이름 변경', 'Rename')),
                  onTap: () => Navigator.pop(sheetContext, 'rename'),
                ),
                ListTile(
                  leading: Icon(
                    item.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  title: Text(
                    item.isFavorite
                        ? _t('즐겨찾기 해제', 'Remove from favorites')
                        : _t('즐겨찾기', 'Add to favorites'),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'favorite'),
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: Text(_t('보관함으로 이동', 'Move to collection')),
                  subtitle: Text(
                    _collectionById(item.collectionId)?.name ??
                        _t('현재 보관함 없음', 'No collection'),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'collection'),
                ),
                if (Platform.isWindows)
                  ListTile(
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(_t('파일 위치 열기', 'Show in folder')),
                    onTap: () => Navigator.pop(sheetContext, 'reveal'),
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(_t('휴지통으로 이동', 'Move to Trash')),
                  onTap: () => Navigator.pop(sheetContext, 'delete'),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: Text(_t('복원', 'Restore')),
                  onTap: () => Navigator.pop(sheetContext, 'restore'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    _t('완전 삭제', 'Delete permanently'),
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () =>
                      Navigator.pop(sheetContext, 'delete_permanently'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    switch (action) {
      case 'rename':
        await _rename(item);
        break;
      case 'favorite':
        await _toggleFavorite(item);
        break;
      case 'collection':
        await _moveItemsToCollection([item]);
        break;
      case 'reveal':
        await _revealInFolder(item);
        break;
      case 'delete':
        await _confirmDelete(item);
        break;
      case 'restore':
        await _restoreRecording(item);
        break;
      case 'delete_permanently':
        await _confirmPermanentDelete(item);
        break;
    }
  }

  Widget _buildCalendarRecordingTile(RecordingItem item) {
    final duration =
        item.durationMs > 0 ? formatDuration(item.duration) : '--:--';

    return CalendarAgendaRecordingTile(
      title: item.displayTitle,
      metaLabel: '${formatRecordingDate(item.createdAt.toLocal())} · $duration',
      preview: _recordingPreview(item),
      hasTranscript: item.hasTranscript,
      maxPreviewLines: 4,
      onTap: () {
        setState(() {
          _selectedRecordingId = item.id;
          _workspaceView = _WorkspaceView.records;
        });
      },
      onLongPress: () => unawaited(_showRecordingActions(item)),
      onDoubleTap: () => unawaited(_rename(item)),
      menuTooltip: _t('기록 메뉴', 'Recording menu'),
      renameLabel: _t('이름 변경', 'Rename'),
      deleteLabel: _t('삭제', 'Delete'),
      onRename: () => unawaited(_rename(item)),
      onDelete: () => unawaited(_confirmDelete(item)),
      revealLabel: Platform.isWindows ? _t('파일 위치 열기', 'Show in folder') : null,
      onReveal: Platform.isWindows ? () => unawaited(_revealInFolder(item)) : null,
    );
  }

  Widget _buildCalendarWorkspace() {
    final scheme = Theme.of(context).colorScheme;
    final localNow = DateTime.now();
    final selectedDate = _selectedCalendarDate;
    final selectedItems = _itemsForDate(selectedDate);
    final daysInMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final itemCounts = <int, int>{
      for (var day = 1; day <= daysInMonth; day++)
        day: _itemsForDate(
          DateTime(_calendarMonth.year, _calendarMonth.month, day),
        ).length,
    };
    final sameDisplayedMonth = selectedDate.year == _calendarMonth.year &&
        selectedDate.month == _calendarMonth.month;
    final selectedDay = sameDisplayedMonth ? selectedDate.day : null;
    final todayDay =
        localNow.year == _calendarMonth.year && localNow.month == _calendarMonth.month
            ? localNow.day
            : null;
    final weekdays = _useEnglish
        ? const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        : const ['일', '월', '화', '수', '목', '금', '토'];
    final weekdayNames = _useEnglish
        ? const [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ]
        : const ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];

    String two(int value) => value.toString().padLeft(2, '0');

    // Local-time date display for the selected agenda day.
    final selectedDateLabel = _useEnglish
        ? '${selectedDate.year}-${two(selectedDate.month)}-${two(selectedDate.day)} '
            '(${weekdayNames[selectedDate.weekday % 7]})'
        : '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일 '
            '${weekdayNames[selectedDate.weekday % 7]}';

    Widget agendaHeader() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedDateLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  _useEnglish
                      ? '${selectedItems.length} recordings'
                      : '${selectedItems.length}개의 기록',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${selectedItems.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      );
    }

    Widget agendaEmpty() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                _t(
                  '이 날짜에는 기록이 없습니다.',
                  'No recordings on this date.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    Widget calendarCard({required bool bounded}) {
      final grid = CalendarMonthGridView(
        year: _calendarMonth.year,
        month: _calendarMonth.month,
        weekdays: weekdays,
        selectedDay: selectedDay,
        todayDay: todayDay,
        itemCounts: itemCounts,
        weekOnly: _calendarWeekView,
        cellAspectRatio: 1.12,
        onDaySelected: (day) => setState(() {
          _selectedCalendarDate =
              DateTime(_calendarMonth.year, _calendarMonth.month, day);
        }),
      );

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: _t('이전 달', 'Previous month'),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month - 1,
                        );
                        final lastDay = DateTime(_calendarMonth.year,
                            _calendarMonth.month + 1, 0).day;
                        _selectedCalendarDate = DateTime(_calendarMonth.year,
                            _calendarMonth.month,
                            _selectedCalendarDate.day.clamp(1, lastDay));
                      });
                    },
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      _useEnglish
                          ? _calendarMonth.year.toString() +
                              '.' +
                              _calendarMonth.month.toString().padLeft(2, '0')
                          : _calendarMonth.year.toString() +
                              '년 ' +
                              _calendarMonth.month.toString() +
                              '월',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final now = DateTime.now();
                      setState(() {
                        _calendarMonth = DateTime(now.year, now.month);
                        _selectedCalendarDate = now;
                      });
                    },
                    child: Text(_t('오늘', 'Today')),
                  ),
                  IconButton(
                    tooltip: _t('다음 달', 'Next month'),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(
                          _calendarMonth.year,
                          _calendarMonth.month + 1,
                        );
                        final lastDay = DateTime(_calendarMonth.year,
                            _calendarMonth.month + 1, 0).day;
                        _selectedCalendarDate = DateTime(_calendarMonth.year,
                            _calendarMonth.month,
                            _selectedCalendarDate.day.clamp(1, lastDay));
                      });
                    },
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (bounded)
                Expanded(child: SingleChildScrollView(child: grid))
              else
                grid,
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _calendarWeekView = !_calendarWeekView,
                  ),
                  icon: Icon(
                    _calendarWeekView
                        ? Icons.calendar_view_month_rounded
                        : Icons.view_week_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _calendarWeekView
                        ? _t('월 보기', 'Month view')
                        : _t('주 보기', 'Week view'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final agendaItems = <Widget>[
      for (final item in selectedItems) _buildCalendarRecordingTile(item),
    ];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Wide: month on the left, wide agenda on the right.
          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: calendarCard(bounded: true)),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(15, 15, 15, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          agendaHeader(),
                          const SizedBox(height: 10),
                          Expanded(
                            child: selectedItems.isEmpty
                                ? agendaEmpty()
                                : ListView(
                                    children: agendaItems,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          // Narrow phones: a single scrollable column. The month grid stays
          // compact for dates/dots while the agenda below gets the full width
          // for long Korean titles and multi-line previews.
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            children: [
              calendarCard(bounded: false),
              const SizedBox(height: 12),
              agendaHeader(),
              const SizedBox(height: 8),
              if (selectedItems.isEmpty)
                agendaEmpty()
              else
                ...agendaItems,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMobileScopeSelector() {
    final activeCount = _items.where((item) => !item.isDeleted).length;
    final favoriteCount =
        _items.where((item) => !item.isDeleted && item.isFavorite).length;
    final trashCount = _items.where((item) => item.isDeleted).length;
    final selectedScope =
        _libraryScope == 'collections' || _collectionFolderOpen
            ? 'collections'
            : _libraryScope;

    return MobileLibraryScopeBar(
      selectedScope: selectedScope,
      onScopeSelected: (next) {
        _clearBatchSelection();
        setState(() {
          _libraryScope = next;
          if ((next == 'trash' || next == 'collections') &&
              _workspaceView == _WorkspaceView.calendar) {
            _workspaceView = _WorkspaceView.records;
          }
        });
      },
      tabs: [
        MobileScopeTab(
          scope: 'all',
          label: _t('전체', 'All'),
          icon: Icons.folder_open_rounded,
          count: activeCount,
        ),
        MobileScopeTab(
          scope: 'favorites',
          label: _t('즐겨찾기', 'Favorites'),
          icon: Icons.star_outline_rounded,
          count: favoriteCount,
        ),
        MobileScopeTab(
          scope: 'collections',
          label: _t('보관함', 'Collections'),
          icon: Icons.folder_copy_outlined,
          count: _collections.length,
        ),
        MobileScopeTab(
          scope: 'trash',
          label: _t('휴지통', 'Trash'),
          icon: Icons.delete_outline_rounded,
          count: trashCount,
        ),
      ],
    );
  }

  Widget _buildCollectionBrowser() {
    final openId = _collectionFolderOpen ? _currentCollectionId : null;
    final openCollection = _collectionById(openId);
    final openItems = openId == null ? const <RecordingItem>[] : _scopeItems();
    final openDuration = Duration(
      milliseconds:
          openItems.fold<int>(0, (sum, item) => sum + item.durationMs),
    );

    return CollectionBrowserView(
      collections: [
        for (final collection in _collections)
          CollectionFolderData(
            id: collection.id,
            name: collection.name,
            recordingCount: _collectionRecordingCount(collection.id),
          ),
      ],
      title: _t('보관함', 'Collections'),
      subtitle: _collections.isEmpty
          ? _t('녹음을 정리할 폴더를 만들어 보세요.',
              'Create a folder to organize recordings.')
          : _t('보관함 ${_collections.length}개',
              '${_collections.length} collections'),
      createLabel: _t('새 보관함', 'New collection'),
      createTooltip: _t('새 보관함', 'New collection'),
      recordingCountLabel: (count) => _t('$count개', '$count items'),
      backLabel: _t('보관함 목록', 'All collections'),
      renameLabel: _t('이름 변경', 'Rename'),
      deleteLabel: _t('보관함 삭제', 'Delete collection'),
      menuTooltip: _t('보관함 메뉴', 'Collection menu'),
      emptyTitle: _t('아직 보관함이 없습니다.', 'No collections yet.'),
      emptyBody: _t(
        '녹음을 주제별로 정리하려면 보관함을 만들어 보세요.',
        'Create a collection to group related recordings.',
      ),
      openCollectionId: openId,
      openCollectionName: openCollection?.name,
      openCollectionSummary: openId == null
          ? null
          : openItems.isEmpty
              ? _t('기록 없음', 'No recordings')
              : _t(
                  '${openItems.length}개 · ${formatDuration(openDuration)}',
                  '${openItems.length} items · ${formatDuration(openDuration)}',
                ),
      openCollectionBody: openId == null
          ? null
          : _buildCollectionRecordingsList(openItems),
      onCreate: () => unawaited(_createCollection()),
      onBack: _closeCollectionFolder,
      onOpen: _openCollection,
      onRename: (id) {
        final collection = _collectionById(id);
        if (collection != null) unawaited(_renameCollection(collection));
      },
      onDelete: (id) {
        final collection = _collectionById(id);
        if (collection != null) unawaited(_deleteCollection(collection));
      },
    );
  }

  Widget _buildMobileScopeBody(List<RecordingItem> filtered) {
    if (_libraryScope == 'collections' || _collectionFolderOpen) {
      return _buildCollectionBrowser();
    }
    return _buildMobileRecordsList(filtered);
  }

  Widget _buildMobileRecordsList(List<RecordingItem> items) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildSidebarHeader(),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(searchEmpty: _query.isNotEmpty)
              : DragSelectionList(
                  ids: items.map((item) => item.id).toList(),
                  selected: _batchSelectedIds,
                  onSelectionChanged: _setBatchSelection,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildCompactRecordingTile(
                      item,
                      onTap: () => unawaited(_showRecordingDetails(item)),
                      dragSelection: true,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCollectionRecordingsList(List<RecordingItem> items) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? items
        : items.where((item) {
            final collection = _collectionById(item.collectionId);
            final haystack = [
              item.displayTitle,
              item.fileName,
              item.transcript ?? '',
              collection?.name ?? '',
              formatRecordingDate(item.createdAt),
            ].join(' ').toLowerCase();
            return haystack.contains(q);
          }).toList();

    return _buildMobileRecordsList(filtered);
  }

  Widget _buildRecordingLibrary(List<RecordingItem> filtered) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 920;

        if (desktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDesktopNavigation(),
              Expanded(
                child: _workspaceView == _WorkspaceView.calendar
                    ? _buildCalendarWorkspace()
                    : Row(
                        children: [
                          Container(
                            width: 326,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLowest,
                              border: Border(
                                right: BorderSide(color: scheme.outlineVariant),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildSidebarHeader(),
                                Divider(height: 1, color: scheme.outlineVariant),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? _buildEmptyState(
                                          searchEmpty: _query.isNotEmpty,
                                        )
                                      : DragSelectionList(
                                          ids: filtered.map((item) => item.id).toList(),
                                          selected: _batchSelectedIds,
                                          onSelectionChanged: _setBatchSelection,
                                          itemBuilder: (context, index) {
                                            final item = filtered[index];
                                            return _buildCompactRecordingTile(
                                              item,
                                              onTap: () => setState(
                                                () => _selectedRecordingId =
                                                    item.id,
                                              ),
                                              dragSelection: true,
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _selectedFrom(filtered) == null
                                ? _buildEmptyState(
                                    searchEmpty: _query.isNotEmpty,
                                  )
                                : ColoredBox(
                                    color: scheme.surface,
                                    child: SingleChildScrollView(
                                      child: _buildRecordingCard(
                                        _selectedFrom(filtered)!,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: SegmentedButton<_WorkspaceView>(
                segments: [
                  ButtonSegment(
                    value: _WorkspaceView.records,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(_t('기록', 'Records')),
                  ),
                  ButtonSegment(
                    value: _WorkspaceView.calendar,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(_t('캘린더', 'Calendar')),
                  ),
                ],
                selected: {_workspaceView},
                onSelectionChanged: (value) {
                  setState(() => _workspaceView = value.first);
                },
              ),
            ),
            _buildMobileScopeSelector(),
            Expanded(
              child: _workspaceView == _WorkspaceView.calendar
                  ? _buildCalendarWorkspace()
                  : _buildMobileScopeBody(filtered),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState({required bool searchEmpty}) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                searchEmpty
                    ? Icons.search_off_rounded
                    : Icons.mic_none_rounded,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              searchEmpty
                  ? _t('검색 결과가 없습니다.', 'No results found.')
                  : _t('아직 저장된 녹음이 없습니다.', 'No recordings yet.'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              searchEmpty
                  ? _t('다른 검색어로 다시 검색해 보세요.', 'Try another search.')
                  : _t('녹음하거나 파일을 가져와 첫 기록을 만들어 보세요.', 'Record something or import a file to create your first entry.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void deactivate() {
    _viewActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _viewActive = true;
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _completeSubscription?.cancel();
    _searchController.dispose();
    _recordingDetailChanges.dispose();
    unawaited(_player.dispose());
    unawaited(_recording.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;

    final mainContent = SafeArea(
      child: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildRecordingLibrary(filtered),
          ),
        ],
      ),
    );

    final supportsDesktopDrop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    final body = supportsDesktopDrop
        ? DropTarget(
            onDragEntered: (_) {
              if (mounted && !_isRecording) {
                setState(() => _draggingFiles = true);
              }
            },
            onDragExited: (_) {
              if (mounted) {
                setState(() => _draggingFiles = false);
              }
            },
            onDragDone: (detail) {
              if (mounted) {
                setState(() => _draggingFiles = false);
              }
              unawaited(
                _importAudioPaths(detail.files.map((file) => file.path)),
              );
            },
            child: Stack(
              children: [
                mainContent,
                if (_draggingFiles)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download_outlined,
                              size: 46,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '여기에 놓아 가져오기',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'WAV · M4A · MP3 · MP4 · WebM',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : mainContent;

    final content = Scaffold(body: body);

    if (Platform.isAndroid) {
      return WithForegroundTask(child: content);
    }
    return content;
  }

}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.centerLineColor,
  });

  final List<double> peaks;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Color centerLineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || size.width <= 0 || size.height <= 0) return;

    final center = size.height / 2;
    final linePaint = Paint()
      ..color = centerLineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      linePaint,
    );

    final barWidth = size.width / peaks.length;
    final activeX = size.width * progress.clamp(0.0, 1.0);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth.clamp(1.2, 3.0);

    for (var i = 0; i < peaks.length; i++) {
      final x = (i + 0.5) * barWidth;
      final amplitude = peaks[i].clamp(0.03, 1.0);
      final halfHeight = (size.height * 0.42) * amplitude;
      paint.color = x <= activeX ? activeColor : inactiveColor;

      canvas.drawLine(
        Offset(x, center - halfHeight),
        Offset(x, center + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.peaks != peaks ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}

class _SttProviderCard extends StatelessWidget {
  const _SttProviderCard({
    required this.provider,
    required this.selected,
    required this.installed,
    required this.supported,
    required this.enabled,
    required this.onTap,
    this.useEnglish = false,
  });

  final bool useEnglish;
  String _t(String ko, String en) => useEnglish ? en : ko;
  final TranscriptionProvider provider;
  final bool selected;
  final bool? installed;
  final bool supported;
  final bool enabled;
  final VoidCallback onTap;

  IconData get _icon => switch (provider) {
        TranscriptionProvider.groq => Icons.bolt_rounded,
        TranscriptionProvider.cloudflare => Icons.cloud_outlined,
        TranscriptionProvider.localSenseVoice => Icons.speed_rounded,
        TranscriptionProvider.localWhisper => Icons.language_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: !supported
          ? scheme.surfaceContainerLow.withValues(alpha: 0.55)
          : selected
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled && supported ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected && supported
                  ? scheme.primary
                  : scheme.outlineVariant,
              width: selected && supported ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _icon,
                  size: 20,
                  color: selected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          provider.label,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        _SttMiniBadge(text: _t(provider.categoryLabel, provider.isLocal ? 'Local' : 'Cloud')),
                        if (provider == TranscriptionProvider.groq)
                          _SttMiniBadge(text: _t('기본 추천', 'Recommended')),
                        if (provider ==
                            TranscriptionProvider.localSenseVoice)
                          _SttMiniBadge(text: _t('로컬 추천', 'Local pick')),
                        if (!supported)
                          _SttMiniBadge(text: _t('현재 언어 미지원', 'Language not supported')),
                        if (installed != null)
                          _SttMiniBadge(
                            text: installed! ? _t('설치됨', 'Installed') : _t('다운로드 필요', 'Download required'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.headlineFor(useEnglish),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _SttMiniBadge(text: _t('속도 ${provider.speedLabel}', 'Speed: ${provider.speedLabelFor(true)}')),
                        _SttMiniBadge(
                          text: _t('정확도 ${provider.accuracyLabel}', 'Accuracy: ${provider.accuracyLabelFor(true)}'),
                        ),
                        _SttMiniBadge(text: _t(provider.privacyLabel, provider.isLocal ? 'On device' : 'Cloud upload')),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      provider.quotaLabelFor(useEnglish),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      provider.strengthFor(useEnglish),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _t('주의: ${provider.tradeoff}', 'Note: ${provider.tradeoffFor(true)}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                !supported
                    ? Icons.block_rounded
                    : selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected && supported
                    ? scheme.primary
                    : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SttMiniBadge extends StatelessWidget {
  const _SttMiniBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({
    required this.title,
    required this.progress,
    required this.primaryText,
    required this.secondaryText,
  });

  final String title;
  final double? progress;
  final String primaryText;
  final String secondaryText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.data_usage_rounded, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            primaryText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 6,
              borderRadius: BorderRadius.circular(99),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            secondaryText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

