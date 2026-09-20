import 'package:flutter/material.dart';

import '../models/recording_item.dart';
import '../models/transcription_result.dart';
import '../utils/formatters.dart';

class TranscriptEditorResult {
  const TranscriptEditorResult({
    required this.text,
    required this.segments,
    required this.speakerLabels,
  });

  final String text;
  final List<TranscriptSegment> segments;
  final Map<int, String> speakerLabels;
}

class TranscriptEditorDialog extends StatefulWidget {
  const TranscriptEditorDialog({
    super.key,
    required this.item,
    required this.useEnglish,
  });

  final RecordingItem item;
  final bool useEnglish;

  static Future<TranscriptEditorResult?> show(
    BuildContext context, {
    required RecordingItem item,
    required bool useEnglish,
  }) {
    return showDialog<TranscriptEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TranscriptEditorDialog(
        item: item,
        useEnglish: useEnglish,
      ),
    );
  }

  @override
  State<TranscriptEditorDialog> createState() => _TranscriptEditorDialogState();
}

class _TranscriptEditorDialogState extends State<TranscriptEditorDialog> {
  late final TextEditingController _fullTextController;
  late final List<TextEditingController> _segmentControllers;
  final Map<int, TextEditingController> _speakerControllers = {};

  String _t(String ko, String en) => widget.useEnglish ? en : ko;

  @override
  void initState() {
    super.initState();
    _fullTextController = TextEditingController(
      text: widget.item.transcript ?? '',
    );
    _segmentControllers = widget.item.segments
        .map((segment) => TextEditingController(text: segment.text))
        .toList();

    final speakers = widget.item.segments
        .map((segment) => segment.speaker)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    for (final speaker in speakers) {
      _speakerControllers[speaker] = TextEditingController(
        text: widget.item.speakerLabels[speaker] ?? '',
      );
    }
  }

  @override
  void dispose() {
    _fullTextController.dispose();
    for (final controller in _segmentControllers) {
      controller.dispose();
    }
    for (final controller in _speakerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final labels = <int, String>{};
    for (final entry in _speakerControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) labels[entry.key] = value;
    }

    final segments = <TranscriptSegment>[];
    for (var i = 0; i < widget.item.segments.length; i++) {
      final text = _segmentControllers[i].text.trim();
      if (text.isEmpty) continue;
      segments.add(widget.item.segments[i].withText(text));
    }

    final text = segments.isNotEmpty
        ? segments.map((segment) => segment.text).join(' ')
        : _fullTextController.text.trim();

    Navigator.pop(
      context,
      TranscriptEditorResult(
        text: text,
        segments: segments,
        speakerLabels: labels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 700;
    final speakers = _speakerControllers.keys.toList()..sort();

    return AlertDialog(
      insetPadding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      title: Text(_t('전사문 수정', 'Edit transcript')),
      content: SizedBox(
        width: compact ? double.maxFinite : 760,
        height: compact ? MediaQuery.sizeOf(context).height * 0.72 : 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t(
                '수정 내용은 이 녹음에만 저장되고 원본 오디오는 변경되지 않습니다.',
                'Edits are saved only to this recording. The original audio is not changed.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (speakers.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                _t('화자 이름', 'Speaker names'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final speaker in speakers)
                    SizedBox(
                      width: compact ? double.infinity : 220,
                      child: TextField(
                        controller: _speakerControllers[speaker],
                        maxLength: 40,
                        decoration: InputDecoration(
                          labelText: _t(
                            '화자 ${speaker + 1}',
                            'Speaker ${speaker + 1}',
                          ),
                          hintText: _t('예: 진행자', 'e.g. Host'),
                          counterText: '',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ] else
              const SizedBox(height: 14),
            Expanded(
              child: widget.item.segments.isEmpty
                  ? TextField(
                      controller: _fullTextController,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        labelText: _t('전사 내용', 'Transcript'),
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.item.segments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final segment = widget.item.segments[index];
                        final speaker = segment.speaker;
                        final speakerText = speaker == null
                            ? null
                            : (_speakerControllers[speaker]?.text.trim().isNotEmpty == true
                                ? _speakerControllers[speaker]!.text.trim()
                                : _t(
                                    '화자 ${speaker + 1}',
                                    'Speaker ${speaker + 1}',
                                  ));
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${formatTimestamp(segment.startSeconds)}–'
                                    '${formatTimestamp(segment.endSeconds)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  if (speakerText != null) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        speakerText,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _segmentControllers[index],
                                minLines: 2,
                                maxLines: 6,
                                decoration: InputDecoration(
                                  hintText: _t(
                                    '이 구간의 전사 내용을 수정하세요.',
                                    'Edit this transcript segment.',
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t('취소', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(_t('저장', 'Save')),
        ),
      ],
    );
  }
}
