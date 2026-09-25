import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Build-time bundle checks only; these do not execute models on a phone.
/// Resolve package locations from Dart's package config, not a host-specific
/// PUB_CACHE path. Generating an iOS runner must not break this test suite.
void main() {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final roots = <String, Uri>{
    for (final package in config['packages'] as List<dynamic>)
      package['name'] as String:
          configFile.uri.resolve('${(package['rootUri'] as String).replaceFirst(RegExp(r'/$'), '')}/'),
  };

  File packageFile(String name, String relative) {
    expect(roots, contains(name));
    return File.fromUri(roots[name]!.resolve(relative));
  }

  test('local transcription has Android and iOS runtime packages', () {
    for (final name in ['sherpa_onnx', 'sherpa_onnx_android_arm64',
      'sherpa_onnx_android_armeabi', 'sherpa_onnx_android_x86_64',
      'sherpa_onnx_ios']) {
      expect(roots, contains(name));
    }
  });

  for (final entry in {'arm64': 'arm64-v8a', 'armeabi': 'armeabi-v7a',
    'x86_64': 'x86_64'}.entries) {
    test('Android ${entry.value} contains both native runtime libraries', () {
      for (final library in ['libsherpa-onnx-c-api.so', 'libonnxruntime.so']) {
        final file = packageFile('sherpa_onnx_android_${entry.key}',
            'android/src/main/jniLibs/${entry.value}/$library');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(file.lengthSync(), greaterThan(0));
      }
    });
  }

  test('iOS runtime provides an arm64 device framework', () {
    final binary = packageFile('sherpa_onnx_ios',
        'ios/sherpa_onnx_ios/SherpaOnnxC.xcframework/ios-arm64/'
        'SherpaOnnxC.framework/SherpaOnnxC');
    expect(binary.existsSync(), isTrue, reason: binary.path);
    expect(binary.lengthSync(), greaterThan(0));
  });
}
