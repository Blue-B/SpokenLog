// Run with the project's package_config.json and three absolute paths:
// dart --packages=.dart_tool/package_config.json tool/windows/smoke_sensevoice.dart
//   <Windows release directory> <SenseVoice model directory> <non-sensitive WAV>
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'package:voice_transcriber/services/sherpa_runtime.dart';

void main(List<String> args) {
  if (args.length != 3 || !Platform.isWindows) {
    throw ArgumentError('Windows only: <release directory> <model directory> <WAV>');
  }
  initializeSherpaRuntime(libraryDirectory: args[0]);
  final recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
    model: sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: '${args[1]}/model.int8.onnx',
        language: 'auto',
        useInverseTextNormalization: true,
      ),
      tokens: '${args[1]}/tokens.txt',
      numThreads: 4,
    ),
  ));
  try {
    final wave = sherpa.readWave(args[2]);
    if (wave.sampleRate <= 0 || wave.samples.isEmpty) {
      throw StateError('The WAV must contain readable audio.');
    }
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      if (text.isEmpty) throw StateError('Transcription was empty.');
      stdout.writeln(text);
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
