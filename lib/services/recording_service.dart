import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/recording_collection.dart';
import '../models/recording_item.dart';
import '../models/transcription_result.dart';
import '../utils/wav_duration.dart';
import 'background_recording_service.dart';

class RecordingService {
  static const supportedImportExtensions = <String>[
    'wav',
    'm4a',
    'mp3',
    'mp4',
    'webm',
  ];

  static bool isSupportedImportPath(String path) {
    final lower = path.toLowerCase();
    return supportedImportExtensions.any(
      (extension) => lower.endsWith('.$extension'),
    );
  }

  final AudioRecorder _recorder = AudioRecorder();
  final BackgroundRecordingService _background = BackgroundRecordingService();

  Directory? _activeSessionDir;
  DateTime? _activeSessionStartedAt;
  DateTime? _activeResumeAt;
  Duration _activeRecordedDuration = Duration.zero;
  String? _activeAudioPath;
  bool _stopRequested = false;
  bool _paused = false;
  String? _activeTitle;
  Timer? _checkpointTimer;

  Future<Directory> _recordingsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}recordings');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _collectionsFile() async {
    final root = await _recordingsDirectory();
    return File(
      '${root.path}${Platform.pathSeparator}.spokenlog_collections.json',
    );
  }

  Future<List<RecordingCollection>> loadCollections() async {
    final file = await _collectionsFile();
    if (!await file.exists()) return const [];

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final collections = decoded
          .whereType<Map>()
          .map(
            (value) => RecordingCollection.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList();
      collections.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return collections;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCollections(
    List<RecordingCollection> collections,
  ) async {
    final file = await _collectionsFile();
    await file.writeAsString(
      jsonEncode(collections.map((value) => value.toJson()).toList()),
      flush: true,
    );
  }

  Future<RecordingCollection> createCollection(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('보관함 이름을 입력해 주세요.');
    }

    final collections = await loadCollections();
    final now = DateTime.now();
    final collection = RecordingCollection(
      id: 'collection_${now.microsecondsSinceEpoch}',
      name: normalized,
      createdAt: now,
    );
    await _saveCollections([...collections, collection]);
    return collection;
  }

  Future<void> renameCollection(
    String id,
    String name,
  ) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('보관함 이름을 입력해 주세요.');
    }

    final collections = await loadCollections();
    final next = collections
        .map(
          (value) => value.id == id
              ? RecordingCollection(
                  id: value.id,
                  name: normalized,
                  createdAt: value.createdAt,
                )
              : value,
        )
        .toList();
    await _saveCollections(next);
  }

  Future<void> deleteCollection(String id) async {
    final collections = await loadCollections();
    await _saveCollections(
      collections.where((value) => value.id != id).toList(),
    );

    final recordings = await loadRecordings();
    for (final item in recordings.where((item) => item.collectionId == id)) {
      await setCollection(item, null);
    }
  }

  Future<bool> hasPermission() => _recorder.hasPermission();

  String _stamp(DateTime now) {
    return '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<String> start() async {
    if (await _recorder.isRecording()) {
      throw Exception('이미 녹음 중입니다.');
    }
    if (!await hasPermission()) {
      throw Exception('마이크 권한이 필요합니다.');
    }

    final root = await _recordingsDirectory();
    final now = DateTime.now();
    final sessionId = 'recording_${_stamp(now)}';
    final sessionDir = Directory(
      '${root.path}${Platform.pathSeparator}$sessionId',
    );
    await sessionDir.create(recursive: true);

    final audioPath =
        '${sessionDir.path}${Platform.pathSeparator}recording.wav';

    _activeSessionDir = sessionDir;
    _activeSessionStartedAt = now;
    _activeResumeAt = null;
    _activeRecordedDuration = Duration.zero;
    _activeAudioPath = audioPath;
    _stopRequested = false;
    _paused = false;
    _activeTitle = null;

    try {
      await _background.start();
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: audioPath,
      );
      _activeResumeAt = DateTime.now();
      await _background.updatePart(1);
      await _writeActiveMetadata(state: 'recording');
      _startCheckpointTimer();
      return sessionId;
    } catch (_) {
      await _background.stop();
      _resetActiveState();
      rethrow;
    }
  }

  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_activeSessionDir == null || _stopRequested) return;
      unawaited(
        _writeActiveMetadata(state: _paused ? 'paused' : 'recording'),
      );
    });
  }

  Duration _activeElapsed() {
    final resumedAt = _activeResumeAt;
    if (resumedAt == null) return _activeRecordedDuration;
    return _activeRecordedDuration + DateTime.now().difference(resumedAt);
  }

  Future<void> pause() async {
    if (_activeSessionDir == null || _paused || _stopRequested) return;

    final resumedAt = _activeResumeAt;
    if (resumedAt != null) {
      _activeRecordedDuration += DateTime.now().difference(resumedAt);
    }
    _activeResumeAt = null;

    await _recorder.pause();
    _paused = true;
    await _writeActiveMetadata(state: 'paused');
  }

  Future<void> resume() async {
    if (_activeSessionDir == null || !_paused || _stopRequested) return;

    await _recorder.resume();
    _paused = false;
    _activeResumeAt = DateTime.now();
    await _writeActiveMetadata(state: 'recording');
  }

  Future<String?> stop() async {
    final dir = _activeSessionDir;
    if (dir == null) {
      if (await _recorder.isRecording()) return _recorder.stop();
      return null;
    }

    _stopRequested = true;

    final resumedAt = _activeResumeAt;
    if (resumedAt != null) {
      _activeRecordedDuration += DateTime.now().difference(resumedAt);
    }
    _activeResumeAt = null;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = _activeAudioPath;
    }

    _paused = false;
    if (path != null) _activeAudioPath = path;

    await _writeActiveMetadata(state: 'completed');
    await _background.stop();

    final sessionPath = dir.path;
    _resetActiveState();
    return sessionPath;
  }

  void _resetActiveState() {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _activeSessionDir = null;
    _activeSessionStartedAt = null;
    _activeResumeAt = null;
    _activeRecordedDuration = Duration.zero;
    _activeAudioPath = null;
    _stopRequested = false;
    _paused = false;
    _activeTitle = null;
  }

  Future<bool> isRecording() => _recorder.isRecording();

  bool get isPaused => _paused;

  Future<void> _writeActiveMetadata({required String state}) async {
    final dir = _activeSessionDir;
    final startedAt = _activeSessionStartedAt;
    final audioPath = _activeAudioPath;
    if (dir == null || startedAt == null || audioPath == null) return;

    final fileName = File(audioPath).uri.pathSegments.last;
    final payload = <String, dynamic>{
      'version': 5,
      'id': dir.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last,
      'title': _activeTitle,
      'createdAt': startedAt.toIso8601String(),
      'state': state,
      'audioLayout': 'single_file',
      'collectionId': null,
      'isFavorite': false,
      'deletedAt': null,
      'chunks': [
        {
          'file': fileName,
          'durationMs': _activeElapsed().inMilliseconds,
        },
      ],
    };

    await File('${dir.path}${Platform.pathSeparator}session.json')
        .writeAsString(jsonEncode(payload), flush: true);
  }

  Future<List<RecordingItem>> loadRecordings() async {
    final root = await _recordingsDirectory();
    final entities = await root.list().toList();
    final items = <RecordingItem>[];

    for (final entity in entities) {
      if (entity is Directory) {
        final item = await _loadSession(entity);
        if (item != null) items.add(item);
      } else if (entity is File && _isSupportedAudioPath(entity.path)) {
        items.add(await _loadLegacyRecording(entity));
      }
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  bool _isSupportedAudioPath(String path) => isSupportedImportPath(path);

  Future<Map<String, dynamic>> _readJsonFile(File file) async {
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<RecordingItem?> _loadSession(Directory dir) async {
    DateTime createdAt = (await dir.stat()).modified;
    final durations = <String, int>{};
    String id =
        dir.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
    String? title;
    String? collectionId;
    var isFavorite = false;
    DateTime? deletedAt;
    String sessionState = '';

    final metadataFile =
        File('${dir.path}${Platform.pathSeparator}session.json');
    final map = await _readJsonFile(metadataFile);
    if (map.isNotEmpty) {
      id = map['id']?.toString() ?? id;
      title = map['title']?.toString();
      collectionId = map['collectionId']?.toString();
      isFavorite = map['isFavorite'] == true;
      deletedAt = DateTime.tryParse(map['deletedAt']?.toString() ?? '');
      sessionState = map['state']?.toString() ?? '';
      createdAt =
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? createdAt;

      final rawChunks = map['chunks'];
      if (rawChunks is List) {
        for (final raw in rawChunks.whereType<Map>()) {
          final chunk = Map<String, dynamic>.from(raw);
          final fileName = chunk['file']?.toString();
          if (fileName != null) {
            durations[fileName] =
                (chunk['durationMs'] as num?)?.toInt() ?? 0;
          }
        }
      }
    }

    final audioFiles = await dir
        .list()
        .where(
          (entity) => entity is File && _isSupportedAudioPath(entity.path),
        )
        .cast<File>()
        .toList();
    audioFiles.sort((a, b) => a.path.compareTo(b.path));
    if (audioFiles.isEmpty) return null;

    if (sessionState == 'recording' || sessionState == 'paused') {
      await _recoverInterruptedSession(
        metadataFile: metadataFile,
        metadata: map,
        audioFiles: audioFiles,
        durations: durations,
      );
    }

    final chunks = audioFiles
        .map(
          (file) => RecordingChunk(
            audioPath: file.path,
            durationMs: durations[file.uri.pathSegments.last] ?? 0,
          ),
        )
        .toList();

    final transcriptFile =
        File('${dir.path}${Platform.pathSeparator}transcript.txt');
    final transcript = await transcriptFile.exists()
        ? await transcriptFile.readAsString()
        : null;
    final transcription = await _readTranscriptionResult(
      File('${dir.path}${Platform.pathSeparator}transcript.json'),
    );
    final segments = transcription?.segments ?? const <TranscriptSegment>[];
    final speakerLabels =
        transcription?.speakerLabels ?? const <int, String>{};

    return RecordingItem(
      id: id,
      title: title,
      createdAt: createdAt,
      chunks: chunks,
      storagePath: dir.path,
      transcript: transcript,
      segments: segments,
      speakerLabels: speakerLabels,
      collectionId: collectionId,
      isFavorite: isFavorite,
      deletedAt: deletedAt,
    );
  }

  Future<RecordingItem> _loadLegacyRecording(File file) async {
    final stat = await file.stat();
    final transcriptFile = File('${file.path}.txt');
    final transcript = await transcriptFile.exists()
        ? await transcriptFile.readAsString()
        : null;
    final transcription = await _readTranscriptionResult(
      File('${file.path}.transcript.json'),
    );
    final segments = transcription?.segments ?? const <TranscriptSegment>[];
    final speakerLabels =
        transcription?.speakerLabels ?? const <int, String>{};
    final metadata = await _readJsonFile(File('${file.path}.meta.json'));

    return RecordingItem(
      id: file.uri.pathSegments.last,
      title: metadata['title']?.toString(),
      createdAt: stat.modified,
      chunks: [RecordingChunk(audioPath: file.path, durationMs: 0)],
      storagePath: file.path,
      transcript: transcript,
      segments: segments,
      speakerLabels: speakerLabels,
      collectionId: metadata['collectionId']?.toString(),
      isFavorite: metadata['isFavorite'] == true,
      deletedAt: DateTime.tryParse(metadata['deletedAt']?.toString() ?? ''),
      isLegacy: true,
    );
  }

  Future<TranscriptionResult?> _readTranscriptionResult(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return TranscriptionResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverInterruptedSession({
    required File metadataFile,
    required Map<String, dynamic> metadata,
    required List<File> audioFiles,
    required Map<String, int> durations,
  }) async {
    for (final audio in audioFiles) {
      if (!audio.path.toLowerCase().endsWith('.wav')) continue;
      final recoveredMs = await readWavDurationMs(audio);
      if (recoveredMs > (durations[audio.uri.pathSegments.last] ?? 0)) {
        durations[audio.uri.pathSegments.last] = recoveredMs;
      }
    }

    metadata['state'] = 'recovered';
    metadata['recoveredAt'] = DateTime.now().toIso8601String();
    final rawChunks = metadata['chunks'];
    if (rawChunks is List) {
      for (final raw in rawChunks.whereType<Map>()) {
        final chunk = Map<String, dynamic>.from(raw);
        final fileName = chunk['file']?.toString();
        if (fileName == null) continue;
        chunk['durationMs'] = durations[fileName] ?? 0;
        raw
          ..clear()
          ..addAll(chunk);
      }
    }
    await metadataFile.writeAsString(jsonEncode(metadata), flush: true);
  }

  Future<RecordingItem> importAudioFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('가져올 파일을 찾을 수 없습니다.');
    }
    if (!isSupportedImportPath(source.path)) {
      throw Exception(
        '지원하지 않는 파일 형식입니다. WAV, M4A, MP3, MP4, WebM을 사용할 수 있습니다.',
      );
    }

    final root = await _recordingsDirectory();
    final now = DateTime.now();
    final suffix = (now.microsecondsSinceEpoch % 1000000)
        .toString()
        .padLeft(6, '0');
    final sessionId = 'import_${_stamp(now)}_$suffix';
    final sessionDir = Directory(
      '${root.path}${Platform.pathSeparator}$sessionId',
    );
    await sessionDir.create(recursive: true);

    final sourceName = source.uri.pathSegments.last;
    final dot = sourceName.lastIndexOf('.');
    final extension = dot >= 0 ? sourceName.substring(dot).toLowerCase() : '';
    final title = dot > 0 ? sourceName.substring(0, dot) : sourceName;
    final targetName = 'imported$extension';
    final targetPath =
        '${sessionDir.path}${Platform.pathSeparator}$targetName';

    try {
      await source.copy(targetPath);

      final metadata = <String, dynamic>{
        'version': 5,
        'id': sessionId,
        'title': title,
        'createdAt': now.toIso8601String(),
        'state': 'completed',
        'audioLayout': 'single_file',
        'imported': true,
        'sourceFileName': sourceName,
        'collectionId': null,
        'isFavorite': false,
        'deletedAt': null,
        'chunks': [
          {
            'file': targetName,
            'durationMs': 0,
          },
        ],
      };

      await File(
        '${sessionDir.path}${Platform.pathSeparator}session.json',
      ).writeAsString(jsonEncode(metadata), flush: true);

      return RecordingItem(
        id: sessionId,
        title: title,
        createdAt: now,
        chunks: [
          RecordingChunk(
            audioPath: targetPath,
            durationMs: 0,
          ),
        ],
        storagePath: sessionDir.path,
      );
    } catch (_) {
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> saveTranscript(
    RecordingItem item,
    TranscriptionResult result,
  ) async {
    final stored = result.speakerLabels.isEmpty && item.speakerLabels.isNotEmpty
        ? result.withSpeakerLabels(item.speakerLabels)
        : result;
    await File(item.transcriptPath).writeAsString(stored.text, flush: true);
    await File(item.transcriptJsonPath)
        .writeAsString(jsonEncode(stored.toJson()), flush: true);
  }

  Future<void> updateTranscript(
    RecordingItem item, {
    required String text,
    required List<TranscriptSegment> segments,
    required Map<int, String> speakerLabels,
  }) {
    final cleanedSegments = segments
        .where((segment) => segment.text.trim().isNotEmpty)
        .toList(growable: false);
    final cleanedLabels = <int, String>{
      for (final entry in speakerLabels.entries)
        if (entry.key >= 0 && entry.value.trim().isNotEmpty)
          entry.key: entry.value.trim(),
    };
    final normalizedText = cleanedSegments.isNotEmpty
        ? cleanedSegments.map((segment) => segment.text.trim()).join(' ')
        : text.trim();

    return saveTranscript(
      item,
      TranscriptionResult(
        text: normalizedText,
        segments: cleanedSegments,
        durationSeconds:
            item.durationMs > 0 ? item.durationMs / 1000 : null,
        speakerLabels: cleanedLabels,
      ),
    );
  }

  Future<Map<String, dynamic>> _recordingMetadata(
    RecordingItem item,
  ) async {
    final file = File(item.metadataPath);
    final metadata = await _readJsonFile(file);

    if (item.isLegacy) {
      metadata['version'] ??= 1;
    } else {
      metadata['version'] ??= 5;
      metadata['id'] ??= item.id;
      metadata['createdAt'] ??= item.createdAt.toIso8601String();
    }
    return metadata;
  }

  Future<void> _writeRecordingMetadata(
    RecordingItem item,
    Map<String, dynamic> metadata,
  ) {
    return File(item.metadataPath)
        .writeAsString(jsonEncode(metadata), flush: true);
  }

  Future<void> renameRecording(RecordingItem item, String title) async {
    final metadata = await _recordingMetadata(item);
    final normalized = title.trim();
    metadata['title'] = normalized.isEmpty ? null : normalized;
    await _writeRecordingMetadata(item, metadata);
  }

  Future<void> setCollection(
    RecordingItem item,
    String? collectionId,
  ) async {
    final metadata = await _recordingMetadata(item);
    metadata['collectionId'] = collectionId;
    await _writeRecordingMetadata(item, metadata);
  }

  Future<void> setFavorite(
    RecordingItem item,
    bool value,
  ) async {
    final metadata = await _recordingMetadata(item);
    metadata['isFavorite'] = value;
    await _writeRecordingMetadata(item, metadata);
  }

  Future<void> moveToTrash(RecordingItem item) async {
    final metadata = await _recordingMetadata(item);
    metadata['deletedAt'] = DateTime.now().toIso8601String();
    await _writeRecordingMetadata(item, metadata);
  }

  Future<void> restoreRecording(RecordingItem item) async {
    final metadata = await _recordingMetadata(item);
    metadata['deletedAt'] = null;
    await _writeRecordingMetadata(item, metadata);
  }

  Future<void> deleteRecording(RecordingItem item) async {
    if (item.isLegacy) {
      for (final chunk in item.chunks) {
        final audio = File(chunk.audioPath);
        if (await audio.exists()) await audio.delete();
      }
      final transcript = File(item.transcriptPath);
      final transcriptJson = File(item.transcriptJsonPath);
      final metadata = File(item.metadataPath);
      if (await transcript.exists()) await transcript.delete();
      if (await transcriptJson.exists()) await transcriptJson.delete();
      if (await metadata.exists()) await metadata.delete();
      return;
    }

    final dir = Directory(item.storagePath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<int> purgeExpiredTrash({
    Duration maxAge = const Duration(days: 30),
  }) async {
    final items = await loadRecordings();
    final now = DateTime.now();
    var removed = 0;

    for (final item in items) {
      final deletedAt = item.deletedAt;
      if (deletedAt == null) continue;
      if (now.difference(deletedAt) < maxAge) continue;
      await deleteRecording(item);
      removed += 1;
    }

    return removed;
  }

  Future<void> permanentlyDeleteRecording(RecordingItem item) {
    return deleteRecording(item);
  }

  Future<void> dispose() async {
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    await _recorder.dispose();
  }
}
