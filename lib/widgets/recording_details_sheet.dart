import 'package:flutter/material.dart';

/// A modal route needs its own subscription: rebuilding the page behind it does
/// not rebuild the modal. The builder also resolves the latest recording data.
class RecordingDetailsSheet extends StatelessWidget {
  const RecordingDetailsSheet({
    super.key,
    required this.changes,
    required this.messengerKey,
    required this.builder,
    this.useEnglish = false,
  });

  final Listenable changes;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final WidgetBuilder builder;
  final bool useEnglish;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: useEnglish ? 'Close recording' : '녹음 상세 닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: changes,
                  builder: (context, _) => SingleChildScrollView(
                    key: const PageStorageKey('recording-detail-scroll'),
                    child: builder(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
