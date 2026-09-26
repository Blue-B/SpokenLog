import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/services/app_storage_service.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory support;
  late AppStorageService storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spokenlog_storage_test_');
    docs = await Directory('${root.path}/documents').create();
    support = await Directory('${root.path}/support').create();
    await Directory('${docs.path}/recordings/session').create(recursive: true);
    await Directory('${support.path}/models/model').create(recursive: true);
    await File(
      '${docs.path}/recordings/session/audio.wav',
    ).writeAsBytes([1, 2, 3]);
    await File(
      '${support.path}/models/model/download.part',
    ).writeAsBytes([4, 5]);
    await File('${docs.path}/export.wav').writeAsBytes([6]);
    await File('${support.path}/unrelated.txt').writeAsString('keep');
    storage = AppStorageService(
      documents: () async => docs,
      support: () async => support,
    );
  });
  tearDown(() => root.delete(recursive: true));

  test('counts partial models and deletes only selected app folder', () async {
    final usage = await storage.usage();
    expect(usage.recordingBytes, 3);
    expect(usage.modelBytes, 2);
    await storage.delete(recordings: false, models: true);
    expect((await storage.usage()).recordingBytes, 3);
    expect((await storage.usage()).modelBytes, 0);
    expect(await File('${docs.path}/export.wav').exists(), isTrue);
    expect(await File('${support.path}/unrelated.txt').exists(), isTrue);
    await storage.delete(recordings: true, models: false);
    expect((await storage.usage()).recordingBytes, 0);
    expect(await docs.exists(), isTrue);
    expect(await support.exists(), isTrue);
  });

  test('no selection preserves data', () async {
    await storage.delete(recordings: false, models: false);
    expect((await storage.usage()).recordingBytes, 3);
    expect((await storage.usage()).modelBytes, 2);
  });

  test(
    'does not traverse nested symlinks or accept a linked data root',
    () async {
      final outside = await Directory('${root.path}/outside').create();
      final file = await File(
        '${outside.path}/keep.wav',
      ).writeAsBytes([9, 9, 9, 9]);
      await Link('${docs.path}/recordings/external').create(outside.path);
      expect((await storage.usage()).recordingBytes, 3);
      await storage.delete(recordings: true, models: false);
      expect(await file.exists(), isTrue);
      await Link('${docs.path}/recordings').create(outside.path);
      await expectLater(
        storage.delete(recordings: true, models: false),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.exists(), isTrue);
    },
    skip: Platform.isWindows
        ? 'Creating symlinks needs Windows developer privileges; exercised on Linux.'
        : false,
  );
}
