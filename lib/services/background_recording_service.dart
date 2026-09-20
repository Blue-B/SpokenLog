import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void voiceRecordingForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_VoiceRecordingTaskHandler());
}

class _VoiceRecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class BackgroundRecordingService {
  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'voice_transcriber_recording',
        channelName: '음성 녹음',
        channelDescription: '화면이 꺼진 동안에도 음성 녹음을 유지합니다.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> start() async {
    if (!Platform.isAndroid) return;

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 32001,
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: 'SpokenLog · 녹음 중',
      notificationText: '화면이 꺼져도 녹음을 계속하고 있습니다.',
      notificationInitialRoute: '/',
      callback: voiceRecordingForegroundCallback,
    );

    if (result is ServiceRequestFailure) {
      throw Exception('Android 백그라운드 녹음 서비스를 시작하지 못했습니다.');
    }
  }

  Future<void> updatePart(int part) async {
    if (!Platform.isAndroid || !await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.updateService(
      notificationTitle: 'SpokenLog · 녹음 중',
      notificationText: '녹음 조각 $part 저장 중 · 화면이 꺼져도 계속 녹음합니다.',
    );
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
