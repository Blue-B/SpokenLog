import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'services/background_recording_service.dart';
import 'services/settings_service.dart';
import 'widgets/model_licenses.dart';
import 'widgets/storage_management_dialog.dart';

RandomAccessFile? _desktopLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerModelLicenses();
  final uninstall = Platform.environment['SPOKENLOG_UNINSTALL'] == '1';
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    try {
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      _desktopLock = await File(
        '${support.path}${Platform.pathSeparator}.spokenlog.lock',
      ).open(mode: FileMode.append);
      await _desktopLock!.lock(FileLock.exclusive);
    } catch (_) {
      await _desktopLock?.close();
      _desktopLock = null;
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AlertDialog(
                title: const Text('SpokenLog를 시작할 수 없습니다'),
                content: const Text(
                  '다른 SpokenLog 창을 모두 닫고 다시 시도해 주세요. '
                  '계속되면 앱 데이터 폴더의 쓰기 권한을 확인하세요. 데이터는 삭제하지 않았습니다.',
                ),
                actions: [
                  TextButton(onPressed: () => exit(1), child: const Text('닫기')),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  if (!uninstall) BackgroundRecordingService.initialize();
  runApp(SpokenLogApp(uninstallMode: uninstall));
}

class SpokenLogApp extends StatelessWidget {
  const SpokenLogApp({super.key, this.uninstallMode = false});
  final bool uninstallMode;

  ThemeData _theme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE96B32),
      brightness: brightness,
    );
    final scheme = brightness == Brightness.light
        ? base.copyWith(
            primary: const Color(0xFFE96B32),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFFFEEE5),
            onPrimaryContainer: const Color(0xFF6A2B12),
            surface: Colors.white,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF8F8F6),
            surfaceContainer: const Color(0xFFF3F3F0),
            surfaceContainerHigh: const Color(0xFFEDEDEA),
            surfaceContainerHighest: const Color(0xFFE7E7E3),
            outline: const Color(0xFFB8B8B2),
            outlineVariant: const Color(0xFFE2E2DE),
          )
        : base;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF8F8F6)
          : scheme.surface,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpokenLog',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.light,
      home: uninstallMode
          ? Scaffold(
              body: Center(
                child: StorageManagementDialog(
                  onClearSettings: SettingsService().clearAppSettings,
                  onUninstallDecision: (proceed) async {
                    await _desktopLock?.close();
                    exit(proceed ? 0 : 1);
                  },
                ),
              ),
            )
          : const HomeScreen(),
    );
  }
}
