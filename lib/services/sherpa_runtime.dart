import 'dart:ffi';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Initialize separately in each inference isolate, as required by sherpa.
void initializeSherpaRuntime({String? libraryDirectory}) {
  if (Platform.isWindows) {
    final directory = libraryDirectory ?? File(Platform.resolvedExecutable).parent.path;
    // Windows can otherwise resolve sherpa's dependency to the older system
    // ONNX Runtime. Its missing API causes a native access violation, not a
    // catchable Dart exception. Always load our bundled runtime first.
    DynamicLibrary.open('$directory/onnxruntime.dll');
    sherpa.initBindings(directory);
  } else {
    sherpa.initBindings(libraryDirectory);
  }
}
