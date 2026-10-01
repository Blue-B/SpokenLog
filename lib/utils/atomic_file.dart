import 'dart:io';

/// Stage beside the destination so replacement stays on the same filesystem.
Future<void> writeStringAtomically(File file, String contents) async {
  final staging = await file.parent.createTemp('.spokenlog-write-');
  try {
    final replacement = File('${staging.path}${Platform.pathSeparator}data');
    await replacement.writeAsString(contents, flush: true);
    await replacement.rename(file.path);
  } finally {
    await staging.delete(recursive: true);
  }
}
