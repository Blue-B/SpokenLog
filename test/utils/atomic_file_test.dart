import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/utils/atomic_file.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('spokenlog-atomic-test-');
  });
  tearDown(() async => root.delete(recursive: true));

  test('readers see a complete old or new JSON during replacement', () async {
    final file = await File(
      '${root.path}/session.json',
    ).writeAsString(jsonEncode({'generation': 0}));
    final contents = jsonEncode({
      'generation': 1,
      'text': List.filled(256 * 1024, 'x').join(),
    });
    var finished = false;
    final write = writeStringAtomically(
      file,
      contents,
    ).whenComplete(() => finished = true);
    try {
      while (!finished) {
        try {
          expect(jsonDecode(await file.readAsString())['generation'], anyOf(0, 1));
        } on FileSystemException catch (error) {
          // Windows may also deny readers briefly during replacement. Check
          // content whenever readable, but do not treat a sharing lock as JSON.
          final code = error.osError?.errorCode;
          if (!Platform.isWindows || (code != 5 && code != 32)) rethrow;
        }
      }
    } finally {
      await write;
    }
    expect(await file.readAsString(), contents);
    expect((await root.list().toList()).length, 1);
  });

  test('replacement waits for a briefly open Windows reader', () async {
    final file = await File('${root.path}/locked.json').writeAsString('old');
    final reader = await file.open();
    final write = writeStringAtomically(file, 'new');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await reader.close();
    await write;
    expect(await file.readAsString(), 'new');
  });

  test(
    'failed replacement cleans staging without deleting the destination',
    () async {
      final destination = await Directory('${root.path}/blocked').create();
      final existing = await File(
        '${destination.path}/existing.txt',
      ).writeAsString('preserve me');
      await expectLater(
        writeStringAtomically(File(destination.path), 'new'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await existing.readAsString(), 'preserve me');
      expect((await root.list().toList()).length, 1);
    },
  );
}
