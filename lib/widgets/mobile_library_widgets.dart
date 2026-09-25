import 'package:flutter/material.dart';

/// Lightweight data passed to [CollectionBrowserView] so the folder list can be
/// rendered (and tested) without depending on the recording service layer.
class CollectionFolderData {
  const CollectionFolderData({
    required this.id,
    required this.name,
    required this.recordingCount,
    this.durationLabel,
  });

  final String id;
  final String name;
  final int recordingCount;
  final String? durationLabel;
}

/// One fixed scope tab (All / Favorites / Collections / Trash).
class MobileScopeTab {
  const MobileScopeTab({
    required this.scope,
    required this.label,
    required this.icon,
    this.count,
  });

  final String scope;
  final String label;
  final IconData icon;
  final int? count;
}

/// Fixed, non-horizontally-scrolling scope selector for mobile.
///
/// Replaces the previous chip row that overflowed off-screen once a few
/// collections existed. Every scope (including Trash) stays reachable because
/// the tabs share the available width equally.
class MobileLibraryScopeBar extends StatelessWidget {
  const MobileLibraryScopeBar({
    super.key,
    required this.tabs,
    required this.selectedScope,
    required this.onScopeSelected,
  });

  final List<MobileScopeTab> tabs;
  final String selectedScope;
  final ValueChanged<String> onScopeSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          for (final tab in tabs)
            Expanded(
              child: _ScopeTab(
                scope: tab.scope,
                label: tab.label,
                icon: tab.icon,
                count: tab.count,
                selected: selectedScope == tab.scope,
                onSelected: onScopeSelected,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    required this.scope,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    this.count,
  });

  final String scope;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onSelected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onSelected(scope),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: foreground,
                      ),
                ),
                if (count != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          height: 1,
                          color: foreground,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single collection folder row/grid cell with rename/delete menu.
class CollectionFolderTile extends StatelessWidget {
  const CollectionFolderTile({
    super.key,
    required this.name,
    required this.recordingCountLabel,
    this.durationLabel,
    this.onTap,
    this.onRename,
    this.onDelete,
    this.renameLabel = 'Rename',
    this.deleteLabel = 'Delete collection',
    this.menuTooltip = 'Collection menu',
  });

  final String name;
  final String recordingCountLabel;
  final String? durationLabel;
  final VoidCallback? onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final String renameLabel;
  final String deleteLabel;
  final String menuTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMenu = onRename != null || onDelete != null;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.folder_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        recordingCountLabel,
                        if (durationLabel != null &&
                            durationLabel!.isNotEmpty)
                          durationLabel!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (hasMenu)
                PopupMenuButton<String>(
                  tooltip: menuTooltip,
                  onSelected: (value) {
                    if (value == 'rename') onRename?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(renameLabel),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(deleteLabel),
                      ),
                  ],
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mobile collections browser.
///
/// When [openCollectionId] is null it renders the vertical folder list/grid.
/// When a collection is open it renders an obvious back bar above
/// [openCollectionBody] (the recordings list owned by the caller).
class CollectionBrowserView extends StatelessWidget {
  const CollectionBrowserView({
    super.key,
    required this.collections,
    required this.title,
    required this.subtitle,
    required this.createLabel,
    required this.onCreate,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onBack,
    required this.backLabel,
    required this.renameLabel,
    required this.deleteLabel,
    required this.menuTooltip,
    required this.emptyTitle,
    required this.emptyBody,
    this.createTooltip,
    this.recordingCountLabel,
    this.openCollectionId,
    this.openCollectionName,
    this.openCollectionSummary,
    this.openCollectionBody,
  });

  final List<CollectionFolderData> collections;
  final String title;
  final String subtitle;
  final String createLabel;
  final String? createTooltip;

  /// Builds the localized per-folder recording count, e.g. "3개".
  /// Defaults to an English "N items" label when omitted.
  final String Function(int count)? recordingCountLabel;
  final String backLabel;
  final String renameLabel;
  final String deleteLabel;
  final String menuTooltip;
  final String emptyTitle;
  final String emptyBody;

  final String? openCollectionId;
  final String? openCollectionName;
  final String? openCollectionSummary;
  final Widget? openCollectionBody;

  final VoidCallback onCreate;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final openId = openCollectionId;
    if (openId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOpenBar(context, openId),
          Expanded(
            child: openCollectionBody ?? const SizedBox.shrink(),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Expanded(
          child: collections.isEmpty
              ? _buildEmpty(context)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 840
                        ? 3
                        : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                    if (columns == 1) {
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        itemCount: collections.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            _buildFolder(context, collections[index]),
                      );
                    }
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: collections.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 92 * textScale,
                      ),
                      itemBuilder: (context, index) =>
                          _buildFolder(context, collections[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFolder(BuildContext context, CollectionFolderData folder) {
    return CollectionFolderTile(
      name: folder.name,
      recordingCountLabel: (recordingCountLabel ?? _defaultCountLabel)(
        folder.recordingCount,
      ),
      durationLabel: folder.durationLabel,
      onTap: () => onOpen(folder.id),
      onRename: () => onRename(folder.id),
      onDelete: () => onDelete(folder.id),
      renameLabel: renameLabel,
      deleteLabel: deleteLabel,
      menuTooltip: menuTooltip,
    );
  }

  String _defaultCountLabel(int count) =>
      count == 1 ? '1 item' : '$count items';

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: Text(createLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenBar(BuildContext context, String openId) {
    final scheme = Theme.of(context).colorScheme;
    void onRenameCurrent() => onRename(openId);
    void onDeleteCurrent() => onDelete(openId);

    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: backLabel,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Icon(Icons.folder_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    openCollectionName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (openCollectionSummary != null)
                    Text(
                      openCollectionSummary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: createTooltip ?? createLabel,
              onPressed: onCreate,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: menuTooltip,
              onSelected: (value) {
                if (value == 'rename') onRenameCurrent();
                if (value == 'delete') onDeleteCurrent();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(renameLabel)),
                PopupMenuItem(value: 'delete', child: Text(deleteLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.create_new_folder_outlined,
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              emptyTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              emptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(createLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Calendar agenda row for a single recording on the selected day.
///
/// The layout is intentionally vertical: unlike the old 7-column month cells,
/// the title/date/preview get the full agenda width so long Korean labels are
/// readable, and the preview can span up to [maxPreviewLines] lines.
class CalendarAgendaRecordingTile extends StatelessWidget {
  const CalendarAgendaRecordingTile({
    super.key,
    required this.title,
    required this.metaLabel,
    required this.preview,
    this.hasTranscript = false,
    this.maxPreviewLines = 4,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.menuTooltip = 'Recording menu',
    this.renameLabel = 'Rename',
    this.deleteLabel = 'Delete',
    this.revealLabel,
    this.onReveal,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final String metaLabel;
  final String preview;
  final bool hasTranscript;
  final int maxPreviewLines;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final String menuTooltip;
  final String renameLabel;
  final String deleteLabel;
  final String? revealLabel;
  final VoidCallback? onReveal;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasMenu =
        onRename != null || onDelete != null || onReveal != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      hasTranscript
                          ? Icons.description_outlined
                          : Icons.graphic_eq_rounded,
                      color: scheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (hasMenu)
                    PopupMenuButton<String>(
                      tooltip: menuTooltip,
                      padding: EdgeInsets.zero,
                      onSelected: (action) {
                        switch (action) {
                          case 'rename':
                            onRename?.call();
                            break;
                          case 'reveal':
                            onReveal?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        if (onRename != null)
                          PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 18),
                                const SizedBox(width: 9),
                                Text(renameLabel),
                              ],
                            ),
                          ),
                        if (onReveal != null && revealLabel != null)
                          PopupMenuItem(
                            value: 'reveal',
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open_outlined,
                                    size: 18),
                                const SizedBox(width: 9),
                                Text(revealLabel!),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: scheme.error,
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  deleteLabel,
                                  style: TextStyle(color: scheme.error),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                metaLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                preview,
                maxLines: maxPreviewLines,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive month grid.
///
/// Month cells stay compact for dates and a count dot, while the readings get
/// their width in the agenda view. When [weekOnly] is true a single week row is
/// shown. Day cells surface selection through [onDaySelected].
class CalendarMonthGridView extends StatelessWidget {
  const CalendarMonthGridView({
    super.key,
    required this.year,
    required this.month,
    required this.weekdays,
    required this.onDaySelected,
    this.selectedDay,
    this.todayDay,
    this.itemCounts = const {},
    this.weekOnly = false,
    this.cellAspectRatio = 1.15,
    this.gridPadding = const EdgeInsets.symmetric(vertical: 2),
  });

  final int year;
  final int month;
  final List<String> weekdays;
  final int? selectedDay;
  final int? todayDay;
  final Map<int, int> itemCounts;
  final bool weekOnly;
  final double cellAspectRatio;
  final EdgeInsets gridPadding;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leading = first.weekday % 7;
    final totalCells = leading + daysInMonth;
    final firstCell = weekOnly
        ? (leading + ((selectedDay ?? todayDay ?? 1) - 1)) ~/ 7 * 7
        : 0;
    final cellCount = weekOnly ? 7 : totalCells;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: weekdays
              .map(
                (label) => Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.builder(
          padding: gridPadding,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: cellAspectRatio,
          ),
          itemBuilder: (context, index) {
            final cell = firstCell + index;
            final day = cell - leading + 1;
            if (day < 1 || day > daysInMonth) {
              return const SizedBox.shrink();
            }
            return _DayCell(
              day: day,
              count: itemCounts[day] ?? 0,
              selected: day == selectedDay,
              today: day == todayDay,
              onTap: () => onDaySelected(day),
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(2.5),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : today
                ? scheme.surfaceContainerHigh
                : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.55)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$day',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: selected || today
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color:
                                selected ? scheme.onPrimaryContainer : null,
                          ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 8,
                  child: count > 0
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.primary
                                  : scheme.primary.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
