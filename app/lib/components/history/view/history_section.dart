import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/generated/export.dart';
import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/history_field_label.dart';
import '../../../core/ui/info_section.dart';
import '../../../core/ui/loading_strip.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/common/history_rows.dart';
import '../../../domain/common/item_ref.dart';
import '../../../domain/common/uuid_time.dart';
import '../history_view_model.dart';
import 'history_keys.dart';

/// A version of an item, shown on the second page of the history sheet.
typedef HistoryVersionView = Widget Function(String revisionId);

/// The **History** section: three rows "who did what, when", below them "Show full
/// history".
class HistorySection extends ConsumerWidget {
  const HistorySection({super.key, required this.item, this.versionView});

  final ItemRef item;

  /// A page's text has versions of its own, with "restore" — **in the same list**: a
  /// change that left a version opens it. Two lists side by side showed the same saves
  /// twice, one knowing what changed, the other what the text was.
  ///
  /// The version opens **inside the history sheet**, the list sliding aside like a
  /// page; a second sheet on top of the first looked like something gone wrong.
  final HistoryVersionView? versionView;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(historyViewModelProvider(item))
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (error, _) => NoticeBar.failure(context, error: error),
        data: (state) => state.available
            ? _HistoryBody(versionView: versionView, item: item, state: state)
            : const SizedBox.shrink(),
      );

  /// The full history — opened at the version [open] when a row of the info bar was
  /// tapped, with the list one step back.
  static void _showAll(
    BuildContext context,
    ItemRef item,
    HistoryVersionView? versionView, {
    String? open,
  }) {
    showHiwiskiSheet(
      context: context,
      title: L.of(context).historyTitle,
      // With versions the sheet holds pages that scroll on their own, and keeps its
      // height while they turn.
      scrolls: versionView == null,
      builder: (context) =>
          _AllEntries(item: item, versionView: versionView, open: open),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.versionView,
    required this.item,
    required this.state,
  });

  final HistoryVersionView? versionView;
  final ItemRef item;
  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final history = state.history;
    if (history == null) {
      // Honest instead of empty: the history is not stored on the device.
      return InfoSection(
        label: l.historyTitle,
        emptyLabel: l.historyOffline,
        children: const [],
      );
    }

    final rows = state.rows;
    return InfoSection(
      label: l.historyTitle,
      emptyLabel: l.historyEmpty,
      action: rows.length > 3
          ? TextButton(
              onPressed: () =>
                  HistorySection._showAll(context, item, versionView),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(l.historyAll),
            )
          : null,
      children: [
        for (final row in rows.take(3))
          _HistoryLine(
            row: row,
            isCreation: _isCreation(row, history, item),
            members: state.members,
            onOpenVersion: versionView == null
                ? null
                : (id) => HistorySection._showAll(
                    context,
                    item,
                    versionView,
                    open: id,
                  ),
          ),
      ],
    );
  }
}

/// The full history, and a version opened from it **in the same sheet** — two pages
/// side by side, like a [PageView]: the version slides in, "back" or a swipe brings
/// the list back where it was.
class _AllEntries extends ConsumerStatefulWidget {
  const _AllEntries({
    required this.item,
    required this.versionView,
    required this.open,
  });

  final ItemRef item;
  final HistoryVersionView? versionView;

  /// The version shown first; `null` starts with the list.
  final String? open;

  @override
  ConsumerState<_AllEntries> createState() => _AllEntriesState();
}

class _AllEntriesState extends ConsumerState<_AllEntries> {
  static const _turn = Duration(milliseconds: 250);

  /// The version on the second page; `null` while there is only the list.
  late String? _open = widget.open;
  late final _pages = PageController(initialPage: _open == null ? 0 : 1);

  /// What the pages need, measured: the list, the "back" row and the version.
  double _listHeight = 0;
  double _backHeight = 0;
  double _versionHeight = 0;

  /// The height the sheet has given the pages so far. **It only grows** while the
  /// sheet is open: a sheet that shrank back when turning to a shorter page jumped
  /// just as one sized to each page did.
  double? _height;

  /// Whether a change of [_height] is a growth to animate — the first one is where
  /// the sheet starts.
  bool _grows = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _show(String revisionId) {
    setState(() {
      _open = revisionId;
      _versionHeight = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pages.animateToPage(1, duration: _turn, curve: Curves.easeOutCubic);
      }
    });
  }

  void _back() =>
      _pages.animateToPage(0, duration: _turn, curve: Curves.easeOutCubic);

  void _measured(VoidCallback update) {
    if (!mounted) return;
    update();
    final needed = _open == null
        ? _listHeight
        : max(_listHeight, _backHeight + _versionHeight);
    final height = _height;
    if (height != null && needed <= height) return;
    setState(() {
      _grows = height != null;
      _height = needed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final versionView = widget.versionView;
    final list = ref
        .watch(historyViewModelProvider(widget.item))
        .when(
          skipLoadingOnReload: true,
          loading: () => const LoadingStrip(loading: true),
          error: (error, _) => NoticeBar.failure(context, error: error),
          data: (state) => _EntriesBody(
            item: widget.item,
            state: state,
            onOpenVersion: versionView == null ? null : _show,
          ),
        );
    if (versionView == null) return list;

    final open = _open;
    final pages = PageView(
      controller: _pages,
      // A hard edge, the pages still snapping into place. With the bouncing default
      // on iOS a swipe back went on past the list, and the list followed the finger
      // far to the right.
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      children: [
        SingleChildScrollView(
          child: _MeasureSize(
            onChange: (size) => _measured(() => _listHeight = size.height),
            child: list,
          ),
        ),
        if (open != null)
          Column(
            crossAxisAlignment: .start,
            children: [
              // Always there, also while the version loads or fails to.
              _MeasureSize(
                onChange: (size) => _measured(() => _backHeight = size.height),
                child: TextButton.icon(
                  key: HistoryKeys.versionBack,
                  onPressed: _back,
                  icon: const Icon(HiwiskiSymbols.arrowBack),
                  label: Text(l.historyTitle),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey(open),
                  child: _MeasureSize(
                    onChange: (size) =>
                        _measured(() => _versionHeight = size.height),
                    child: versionView(open),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
    // Back on the list, the version is let go — **once the page has come to rest**.
    // Let go halfway through the swipe, the rest of the gesture had no page left to
    // turn to.
    final settled = NotificationListener<ScrollEndNotification>(
      onNotification: (end) {
        final metrics = end.metrics;
        if (end.depth == 0 &&
            _open != null &&
            metrics.pixels <= metrics.minScrollExtent) {
          setState(() => _open = null);
        }
        return false;
      },
      child: pages,
    );
    // As high as the pages need, no higher than the sheet may be — growing smoothly
    // when a longer version comes in.
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedContainer(
        duration: _grows ? _turn : .zero,
        curve: Curves.easeOutCubic,
        height: min(_height ?? 0, constraints.maxHeight),
        child: settled,
      ),
    );
  }
}

/// Reports its child's size whenever it changes — after the frame, so the parent may
/// rebuild with it.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) => renderObject.onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (measured == _reported) return;
    _reported = measured;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
  }
}

/// One row: "who · what" and below it, when — tapped, the version it left.
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({
    required this.row,
    required this.members,
    required this.onOpenVersion,
    this.isCreation = false,
  });

  final HistoryRow row;
  final bool isCreation;

  /// Whom the actor ids name.
  final List<Member> members;
  final ValueChanged<String>? onOpenVersion;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final entry = row.entry;
    final revision = row.revision;
    final actorId = entry?.actorId ?? revision?.authorId;
    final who =
        members
            .where((member) => member.id == actorId)
            .map((member) => member.displayName)
            .firstOrNull ??
        l.historySomeone;

    final change = switch (entry) {
      HistoryEntry(op: .delete) => l.historyDeleted,
      _? when isCreation => l.historyCreated,
      final entry? => historyChange(l, entry),
      // A version without its change: older than the log, or the losing side of a
      // conflict.
      null when revision?.kind == .conflict => l.historyConflictVersion,
      null => l.historyVersionSaved,
    };
    // In a list's history, a change to one of its tasks names the task.
    final what = switch (entry) {
      HistoryEntry(entryId: _?, :final entryTitle) => l.historyOfEntry(
        entryTitle ?? '',
        change,
      ),
      _ => change,
    };

    final line = Padding(
      padding: const .symmetric(vertical: HiwiskiMetrics.space4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text('$who · $what', style: context.texts.bodyMedium),
                Text(
                  DateFormat.MMMd(locale).add_Hm().format(row.at.toLocal()),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (revision != null && onOpenVersion != null)
            Icon(
              HiwiskiSymbols.chevronRight,
              semanticLabel: l.historyOpenVersion,
              color: context.scheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    return switch ((revision, onOpenVersion)) {
      (final revision?, final open?) => InkWell(
        key: HistoryKeys.version(revision.id),
        onTap: () => open(revision.id),
        child: line,
      ),
      _ => line,
    };
  }
}

class _EntriesBody extends StatelessWidget {
  const _EntriesBody({
    required this.item,
    required this.state,
    required this.onOpenVersion,
  });

  final ItemRef item;
  final HistoryState state;
  final ValueChanged<String>? onOpenVersion;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final value = state.history;
    if (value == null) {
      return Text(l.historyOffline, style: context.texts.bodyMedium);
    }

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final row in state.rows)
          _HistoryLine(
            row: row,
            isCreation: _isCreation(row, value, item),
            members: state.members,
            onOpenVersion: onOpenVersion,
          ),
        const SizedBox(height: HiwiskiMetrics.space12),
        // **Without this note a truncated history looks like a complete
        // one**.
        Text(
          l.historyReachesBack(
            DateFormat.yMMMd(locale).format(value.reachesBack.toLocal()),
          ),
          style: context.texts.bodySmall?.copyWith(
            color: context.scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

bool _isCreation(HistoryRow row, History history, ItemRef item) =>
    switch (row.entry) {
      final entry? => isCreationEntry(
        entry,
        history.entries,
        history.reachesBack,
        item,
      ),
      null => false,
    };

/// Whether [entry] is the item's creation: the oldest entry, of an item created after
/// what the history reaches back to. In a list's history an entry of one of its
/// tasks is measured among that task's entries, by the task's id.
///
/// **The item's age decides, not the entry's.** Retention deletes everything older
/// than [reachesBack], so the oldest entry left is always newer than it — measured by
/// the entry, every item older than the retention period showed its oldest surviving
/// change as "created". A UUIDv7 id carries the creation time; only an id without one
/// (an event from a subscribed calendar) falls back to the entry.
bool isCreationEntry(
  HistoryEntry entry,
  List<HistoryEntry> entries,
  DateTime? reachesBack,
  ItemRef item,
) {
  if (reachesBack == null) return false;
  final entryId = entry.entryId;
  final oldest = entries.lastWhereOrNull((other) => other.entryId == entryId);
  if (oldest == null) return false;
  final created = timeOfUuidV7(entryId ?? item.id) ?? entry.at;
  return entry.seq == oldest.seq && created.isAfter(reachesBack);
}

/// "checked off", "archived", "moved to “Doing”", "changed: Due" — or several of
/// them.
///
/// **Status and archive say which way they went, a card where it went.** As mere field
/// names, checking off and opening again would both read "changed: Status", archiving
/// and restoring both "changed: Archive", every move "changed: Column".
String historyChange(L l, HistoryEntry entry) {
  final fields = entry.fields ?? const [];
  final archive = fields.contains(WireFields.archivedAt)
      ? switch (entry.archived) {
          true => l.historyArchived,
          false => l.historyRestored,
          null => null,
        }
      : null;
  final status = fields.contains(WireFields.status)
      ? switch (entry.status) {
          .done => l.historyCheckedOff,
          .open => l.historyReopened,
          // An older server or a status this app does not know yet: the field name.
          _ => null,
        }
      : null;
  final column = fields.contains(WireFields.columnId)
      ? switch (entry.column) {
          final name? => l.historyMovedTo(name),
          // A column deleted since, or an older server: the field name.
          null => null,
        }
      : null;
  // What the direction already says is not listed again as a field — a card's place
  // in its new column belongs to the move.
  final told = {
    if (status != null) WireFields.status,
    if (archive != null) ...[WireFields.archivedAt, WireFields.archivedBy],
    if (column != null) ...[WireFields.columnId, WireFields.position],
  };
  final rest = fields.where((field) => !told.contains(field)).toList();
  return [
    ?archive,
    ?status,
    ?column,
    if (rest.isNotEmpty || told.isEmpty) l.historyChanged(_fields(l, rest)),
  ].join(', ');
}

String _fields(L l, List<String>? fields) {
  if (fields == null || fields.isEmpty) return '—';
  // Merged and without duplicates: "dueDate" and "dueTime" are both "Due" to the
  // reader, and "Due" twice in one row says nothing any more.
  final labels = <String>[];
  for (final field in fields) {
    final label = historyFieldLabel(l, field);
    if (!labels.contains(label)) labels.add(label);
  }
  return labels.join(', ');
}
