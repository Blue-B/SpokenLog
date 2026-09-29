import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_transcriber/widgets/model_licenses.dart';

void main() {
  test('model licenses are listed with their required attribution', () async {
    registerModelLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final byPackage = {
      for (final entry in entries)
        for (final package in entry.packages)
          package: entry.paragraphs.map((p) => p.text).join('\n'),
    };

    final whisper = byPackage['Whisper models (OpenAI)']!;
    expect(whisper, contains('MIT License'));
    expect(whisper, contains('Copyright (c) 2022 OpenAI'));

    final senseVoice = byPackage['SenseVoiceSmall model (FunASR, Alibaba Group)']!;
    expect(senseVoice, contains('FunASR Model Open Source License Agreement'));
    // The FunASR terms require crediting the source and keeping the model name.
    expect(senseVoice, contains('attribute the source and author information'));
    expect(senseVoice, contains('model name: SenseVoice'));

    final speakers = byPackage['Speaker separation models']!;
    expect(speakers, contains('pyannote segmentation 3.0 (MIT License)'));
    expect(speakers, contains('Apache License 2.0'));
  });
}
