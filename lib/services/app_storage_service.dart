import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AppStorageUsage {
  const AppStorageUsage(
    this.recordings,
    this.models,
    this.recordingBytes,
    this.modelBytes,
  );
  final Directory recordings;
  final Directory models;
  final int recordingBytes;
  final int modelBytes;
}

/// Only the two app data folders, never Documents or Application Support itself.
class AppStorageService {
  AppStorageService({
    Future<Directory> Function()? documents,
    Future<Directory> Function()? support,
  }) : _documents = documents ?? getApplicationDocumentsDirectory,
       _support = support ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _support;

  Future<Directory> _folder(bool models) async {
    final parent = await (models ? _support() : _documents());
    final dir = Directory(
      '${parent.path}${Platform.pathSeparator}${models ? 'models' : 'recordings'}',
    );
    final type = await FileSystemEntity.type(dir.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'The app data folder must be a real directory',
        dir.path,
      );
    }
    return dir;
  }

  Future<int> _bytes(Directory dir) async {
    if (!await dir.exists()) return 0;
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  Future<AppStorageUsage> usage() async {
    final recordings = await _folder(false);
    final models = await _folder(true);
    return AppStorageUsage(
      recordings,
      models,
      await _bytes(recordings),
      await _bytes(models),
    );
  }

  Future<void> delete({required bool recordings, required bool models}) async {
    for (final isModel in [if (recordings) false, if (models) true]) {
      // Resolve again at deletion time; do not trust a UI-provided path.
      final dir = await _folder(isModel);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
