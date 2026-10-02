import 'dart:io';

/// Stage beside the destination so replacement stays on the same filesystem.
Future<void> writeStringAtomically(File file, String contents) async {
  final staging = await file.parent.createTemp('.spokenlog-write-');
  try {
    final replacement = File('${staging.path}${Platform.pathSeparator}data');
    await replacement.writeAsString(contents, flush: true);
    for (var attempt = 0; ; attempt++) {
      try {
        await replacement.rename(file.path);
        break;
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        // Windows readers/antivirus can briefly deny replacement. Never delete
        // the old file to bypass a sharing lock or a persistent access failure.
        if (!Platform.isWindows || (code != 5 && code != 32) || attempt >= 19) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  } finally {
    await staging.delete(recursive: true);
  }
}
