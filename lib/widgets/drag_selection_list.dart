import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// A normal scrolling list until a long press starts a range selection.
class DragSelectionList extends StatefulWidget {
  const DragSelectionList({
    super.key,
    required this.ids,
    required this.selected,
    required this.onSelectionChanged,
    required this.itemBuilder,
  });
  final List<String> ids;
  final Set<String> selected;
  final ValueChanged<Set<String>> onSelectionChanged;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<DragSelectionList> createState() => _DragSelectionListState();
}

class _DragSelectionListState extends State<DragSelectionList> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _rows = <String, GlobalKey>{};
  Timer? _timer;
  int? _anchor;
  int? _lastIndex;
  Offset? _pointer;
  Set<String> _before = {};
  bool _selecting = true;

  void _apply(int index) {
    final anchor = _anchor;
    if (anchor == null || index == _lastIndex) return;
    _lastIndex = index;
    final first = anchor < index ? anchor : index;
    final last = anchor > index ? anchor : index;
    final range = widget.ids.sublist(first, last + 1);
    final selected = {..._before};
    if (_selecting) {
      selected.addAll(range);
    } else {
      selected.removeAll(range);
    }
    widget.onSelectionChanged(selected);
  }

  void _hitTest() {
    final pointer = _pointer;
    if (pointer == null) return;
    for (var index = 0; index < widget.ids.length; index++) {
      final box = _rows[widget.ids[index]]?.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (box.localToGlobal(Offset.zero) & box.size).contains(pointer)) {
        _apply(index);
        return;
      }
    }
  }

  void _start(int index, Offset pointer) {
    _end();
    _anchor = index;
    _before = {...widget.selected};
    _selecting = !_before.contains(widget.ids[index]);
    _pointer = pointer;
    _apply(index);
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final box = _viewport.currentContext?.findRenderObject();
      if (!_scroll.hasClients || box is! RenderBox || _pointer == null) return;
      final y = box.globalToLocal(_pointer!).dy;
      final delta = y < 48
          ? -18.0
          : y > box.size.height - 48
          ? 18.0
          : 0.0;
      if (delta == 0) return;
      final position = _scroll.position;
      final next = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next == position.pixels) return;
      position.jumpTo(next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _anchor != null) _hitTest();
      });
    });
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _anchor = null;
    _lastIndex = null;
    _pointer = null;
  }

  @override
  void didUpdateWidget(covariant DragSelectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.ids, widget.ids)) {
      _end();
      _rows.removeWhere((id, _) => !widget.ids.contains(id));
    }
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: _viewport,
    controller: _scroll,
    padding: const EdgeInsets.symmetric(vertical: 5),
    itemCount: widget.ids.length,
    itemBuilder: (context, index) => GestureDetector(
      key: _rows.putIfAbsent(widget.ids[index], GlobalKey.new),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => _start(index, details.globalPosition),
      onLongPressMoveUpdate: (details) {
        _pointer = details.globalPosition;
        _hitTest();
      },
      onLongPressEnd: (_) => _end(),
      onLongPressCancel: _end,
      child: widget.itemBuilder(context, index),
    ),
  );

  @override
  void dispose() {
    _end();
    _scroll.dispose();
    super.dispose();
  }
}
