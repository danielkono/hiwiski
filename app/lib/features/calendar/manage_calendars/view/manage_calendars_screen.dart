import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/row_card.dart';

import 'package:intl/intl.dart';

import '../../../../components/sharing/view/share_sheet.dart';
import '../../../../components/sharing/view/share_summary_builder.dart';
import '../../../../components/tags/view/tag_widgets.dart';
import '../../../../core/api/hiwiski_failure.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/color_tokens.dart';
import '../../../../core/ui/failure_text.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/calendar/calendar_items.dart';
import '../../../../domain/calendar/calendar_kinds.dart';
import '../../../../domain/common/item_ref.dart';
import '../../view/calendar_keys.dart';
import '../manage_calendars_view_model.dart';
import 'calendar_sheets.dart';

/// "Manage calendars" — three sections:
/// own calendars, subscribed calendars (ICS), own ICS links.
class ManageCalendarsScreen extends ConsumerStatefulWidget {
  const ManageCalendarsScreen({super.key, this.newCalendar = false});

  /// Opens "New calendar" once the screen is there.
  final bool newCalendar;

  @override
  ConsumerState<ManageCalendarsScreen> createState() =>
      _ManageCalendarsScreenState();
}

class _ManageCalendarsScreenState extends ConsumerState<ManageCalendarsScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.newCalendar) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Nothing waits for the sheet; it creates the calendar itself.
      if (mounted) unawaited(showCalendarSheet(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: L.of(context).calManage,
      onBack: () => Navigator.of(context).pop(),
    );
    return ref
        .watch(manageCalendarsViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) => _ManageCalendarsPage(state: state),
        );
  }
}

class _ManageCalendarsPage extends ConsumerWidget {
  const _ManageCalendarsPage({required this.state});

  final ManageCalendarsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final padding = Breakpoint.of(context).pagePadding;
    final calendars = state.all;
    final subscriptions = state.subscriptions;
    final feeds = state.feeds;

    return HiwiskiPage(
      header: PageHeader(
        title: l.calManage,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: ListView(
        padding: padding.add(const .only(bottom: HiwiskiMetrics.space32)),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: HiwiskiMetrics.listMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  _SectionTitle(
                    l.calOwnCalendars,
                    action: Wrap(
                      spacing: HiwiskiMetrics.space8,
                      children: [
                        if (state.hasServer)
                          OutlinedButton.icon(
                            icon: const Icon(
                              HiwiskiSymbols.upload,
                              size: HiwiskiMetrics.icon18,
                            ),
                            label: Text(l.calImportFile),
                            onPressed: () => showIcsImportSheet(context),
                          ),
                        OutlinedButton.icon(
                          icon: const Icon(
                            HiwiskiSymbols.add,
                            size: HiwiskiMetrics.icon18,
                          ),
                          label: Text(l.calNewCalendar),
                          onPressed: () => showCalendarSheet(context),
                        ),
                      ],
                    ),
                  ),
                  RowCard(
                    children: [
                      for (final managed in state.calendars)
                        _CalendarTile(
                          calendar: managed.calendar,
                          feeds: managed.feeds,
                          shareable: state.hasServer,
                          deletable: managed.deletable,
                        ),
                    ],
                  ),
                  // Subscriptions are fetched by the server and the ICS links served
                  // by it: without one there are neither.
                  if (state.hasServer) ...[
                    const SizedBox(height: HiwiskiMetrics.space28),
                    _SectionTitle(
                      l.calSubscriptions,
                      action: OutlinedButton.icon(
                        icon: const Icon(
                          HiwiskiSymbols.addLink,
                          size: HiwiskiMetrics.icon18,
                        ),
                        label: Text(l.calAddSubscription),
                        onPressed: () => showSubscriptionSheet(context),
                      ),
                    ),
                    RowCard(
                      children: [
                        for (final subscription in subscriptions)
                          _SubscriptionTile(
                            subscription: subscription,
                            calendars: calendars,
                            removable: state.removableSubscriptions.contains(
                              subscription.id,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: HiwiskiMetrics.space28),
                    _SectionTitle(
                      l.calFeeds,
                      action: OutlinedButton.icon(
                        icon: const Icon(
                          HiwiskiSymbols.rssFeed,
                          size: HiwiskiMetrics.icon18,
                        ),
                        label: Text(l.calNewFeed),
                        onPressed: () => showFeedSheet(context),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: context.scheme.surfaceContainer,
                        borderRadius: const .all(
                          .circular(HiwiskiMetrics.radiusCard),
                        ),
                      ),
                      padding: const .fromLTRB(
                        HiwiskiMetrics.space16,
                        HiwiskiMetrics.space16,
                        HiwiskiMetrics.space8,
                        HiwiskiMetrics.space12,
                      ),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          Padding(
                            padding: const .only(right: HiwiskiMetrics.space10),
                            child: Text(
                              l.calFeedsNote,
                              style: context.texts.bodyMedium?.copyWith(
                                color: context.scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final feed in feeds)
                            _FeedTile(feed: feed, calendars: calendars),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: HiwiskiMetrics.space28),
                  _SectionTitle(l.calDisplaySection),
                  RowCard(
                    children: [
                      SwitchListTile(
                        key: CalendarKeys.calendarPinnedStrip,
                        secondary: const Icon(HiwiskiSymbols.beachAccess),
                        title: Text(l.calPinnedSetting),
                        subtitle: Text(l.calPinnedSettingHint),
                        value: state.pinnedStrip,
                        onChanged: (pinned) => ref
                            .read(manageCalendarsViewModelProvider.notifier)
                            .setPinnedStrip(pinned),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});

  final String text;
  final Widget? action;

  /// The buttons go to a line of their own when they and the title do not fit side by
  /// side — on the phone two buttons squeezed "Own calendars" into a sliver.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(bottom: HiwiskiMetrics.space10),
    child: Wrap(
      alignment: .spaceBetween,
      crossAxisAlignment: .center,
      spacing: HiwiskiMetrics.space8,
      runSpacing: HiwiskiMetrics.space8,
      children: [
        Text(text, style: context.tokens.text.sectionLabel),
        ?action,
      ],
    ),
  );
}

class _CalendarTile extends ConsumerWidget {
  const _CalendarTile({
    required this.calendar,
    required this.feeds,
    required this.shareable,
    required this.deletable,
  });

  /// Whether it can be shared — not without a server; the row then edits it.
  final bool shareable;

  /// Whether its sheet offers "Delete".
  final bool deletable;

  final Calendar calendar;

  /// The names of the ICS links this calendar is exported through — `rss_feed` in
  /// `pri` when there is one.
  final List<String> feeds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final muted = context.scheme.onSurfaceVariant;

    return InkWell(
      onTap: shareable
          ? () => showShareSheet(
              context,
              item: ItemRef(EntityTypes.calendar, calendar.id),
            )
          : () => showCalendarSheet(
              context,
              calendar: calendar,
              deletable: deletable,
            ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.listRowHeightTall,
        ),
        child: Padding(
          padding: const .fromLTRB(
            HiwiskiMetrics.space16,
            HiwiskiMetrics.space8,
            HiwiskiMetrics.space8,
            HiwiskiMetrics.space8,
          ),
          child: Row(
            children: [
              _Dot(color: context.tokens.accent(accentOf(calendar.colorToken))),
              const SizedBox(width: HiwiskiMetrics.space14),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            calendar.name,
                            overflow: .ellipsis,
                            style: context.texts.bodyLarge?.copyWith(
                              fontWeight: .w500,
                            ),
                          ),
                        ),
                        // Locked by its import: read only, like a subscription.
                        if (calendar.kind == kindImported) ...[
                          const SizedBox(width: HiwiskiMetrics.space4),
                          Icon(
                            HiwiskiSymbols.lock,
                            size: HiwiskiMetrics.icon16,
                            color: muted,
                          ),
                        ],
                      ],
                    ),
                    // Its tags apply to all of its events (calendar_tags.dart) — so
                    // they are shown where the calendar is.
                    if (calendar.tags.isNotEmpty)
                      Padding(
                        padding: const .symmetric(
                          vertical: HiwiskiMetrics.space4,
                        ),
                        child: TagChips(raw: calendar.tags),
                      ),
                    ShareSummaryBuilder(
                      item: ItemRef.calendar(calendar.id),
                      builder: (context, icon, text) => Row(
                        spacing: HiwiskiMetrics.space4,
                        children: [
                          Icon(icon, size: HiwiskiMetrics.icon16, color: muted),
                          Flexible(
                            child: Text(
                              text,
                              overflow: .ellipsis,
                              style: context.texts.bodySmall?.copyWith(
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Only when the calendar is in an ICS link. Faded on every other calendar,
              // the feed symbol read as a disabled "share" — while sharing itself had no
              // button at all, only a tap on the row.
              // A tap explains it — before, it fell through to the row and opened the
              // sharing, which has nothing to do with the export.
              if (feeds.isNotEmpty)
                Tooltip(
                  message: l.calInFeeds(feeds.join(', ')),
                  triggerMode: .tap,
                  child: Padding(
                    padding: const .all(HiwiskiMetrics.space10),
                    child: Icon(
                      HiwiskiSymbols.rssFeed,
                      size: HiwiskiMetrics.icon20,
                      color: context.scheme.primary,
                    ),
                  ),
                ),
              if (shareable)
                IconButton(
                  icon: Icon(
                    HiwiskiSymbols.share,
                    size: HiwiskiMetrics.icon20,
                    color: muted,
                  ),
                  tooltip: l.shareTitle,
                  onPressed: () => showShareSheet(
                    context,
                    item: ItemRef(EntityTypes.calendar, calendar.id),
                  ),
                ),
              IconButton(
                icon: Icon(
                  HiwiskiSymbols.edit,
                  size: HiwiskiMetrics.icon20,
                  color: muted,
                ),
                tooltip: l.actionEdit,
                onPressed: () => showCalendarSheet(
                  context,
                  calendar: calendar,
                  deletable: deletable,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({
    required this.subscription,
    required this.calendars,
    required this.removable,
  });

  final CalendarSubscription subscription;
  final List<Calendar> calendars;

  /// Whether the menu offers "Delete subscription".
  final bool removable;

  /// "Sync now" says when it failed — it used to fail without a word.
  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(manageCalendarsViewModelProvider.notifier)
          .refreshSubscription(subscription);
    } on HiwiskiFailure catch (failure) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(failureText(context, failure))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final locale = Localizations.localeOf(context).toString();
    final calendar = calendars
        .where((row) => row.id == subscription.calendarId)
        .firstOrNull;
    final tokens = context.tokens;

    final interval = switch (subscription.syncInterval) {
      SyncIntervals.hourly => l.calIntervalHourly,
      SyncIntervals.weekly => l.calIntervalWeekly,
      _ => l.calIntervalDaily,
    };

    // "Updated today, 06:00 · daily" / "Error while fetching …" in `error`.
    // A subscription with a broken file **stays in place**, and the
    // error is shown on it.
    final error = subscription.lastError;
    final status = switch ((error, subscription.lastSyncAt)) {
      (final error?, _) when error.isNotEmpty => l.calSyncError(
        failureTextForCode(context, error),
      ),
      (_, null) => l.calSyncNever,
      (_, final syncedAt?) => l.calSyncedAt(
        DateFormat.MMMEd(locale).add_Hm().format(syncedAt.toLocal()),
        interval,
      ),
    };

    return ListTile(
      contentPadding: const .fromLTRB(
        HiwiskiMetrics.space16,
        HiwiskiMetrics.space4,
        HiwiskiMetrics.space8,
        HiwiskiMetrics.space4,
      ),
      minTileHeight: HiwiskiMetrics.listRowHeightTall,
      leading: _Dot(
        color: tokens.accent(
          accentOf(calendar?.colorToken ?? ColorTokens.blue),
        ),
      ),
      title: Text(subscription.name),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: [
          if (subscription.url.isNotEmpty)
            Text(subscription.url, style: tokens.text.monoSmall),
          Text(
            status,
            style: context.texts.bodySmall?.copyWith(
              color: error != null && error.isNotEmpty
                  ? context.scheme.error
                  : context.scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: .min,
        children: [
          IconButton(
            icon: const Icon(HiwiskiSymbols.syncSymbol),
            tooltip: l.calSyncNow,
            onPressed: () => _syncNow(context, ref),
          ),
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(HiwiskiSymbols.syncSymbol),
                onPressed: () => _syncNow(context, ref),
                child: Text(l.calSyncNow),
              ),
              if (calendar != null)
                MenuItemButton(
                  leadingIcon: const Icon(HiwiskiSymbols.visibility),
                  onPressed: () => showShareSheet(
                    context,
                    item: ItemRef(EntityTypes.calendar, calendar.id),
                  ),
                  child: Text(l.shareTitle),
                ),
              if (removable)
                MenuItemButton(
                  leadingIcon: const Icon(HiwiskiSymbols.delete),
                  onPressed: () => _confirmDelete(context, ref),
                  child: Text(l.calDeleteSubscription),
                ),
            ],
            builder: (context, anchor, _) => IconButton(
              icon: const Icon(HiwiskiSymbols.moreVert),
              tooltip: l.actionMore,
              onPressed: () => anchor.isOpen ? anchor.close() : anchor.open(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.calDeleteSubscription),
        content: Text(l.calDeleteSubscriptionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(manageCalendarsViewModelProvider.notifier)
          .deleteSubscription(subscription);
    }
  }
}

class _FeedTile extends ConsumerWidget {
  static const _icsPath = 'ics';
  static const _icsExtension = 'ics';

  const _FeedTile({required this.feed, required this.calendars});

  final CalendarFeed feed;
  final List<Calendar> calendars;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final base =
        ref.watch(manageCalendarsViewModelProvider).value?.serverAddress ?? '';
    // The ICS path is deliberately **outside** the spec: a foreign calendar program
    // knows neither `/api` nor our envelope.
    final address = '$base/$_icsPath/${feed.token}.$_icsExtension';

    return ListTile(
      contentPadding: const .only(top: HiwiskiMetrics.space8),
      title: Text(feed.name),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: [
          Text(address, style: context.tokens.text.monoSmall),
          // Which calendars go out through it — the same ones that carry the feed
          // symbol above.
          Text(
            l.calFeedIncludes(
              [
                for (final calendar in calendars)
                  if (feed.calendarIds.split(',').contains(calendar.id))
                    calendar.name,
              ].join(', '),
            ),
            style: context.texts.bodySmall,
          ),
          Text(
            feed.contentMode == FeedContentModes.busy
                ? l.calFeedContentBusy
                : l.calFeedContentFull,
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: .min,
        children: [
          IconButton(
            icon: const Icon(HiwiskiSymbols.contentCopy),
            tooltip: l.calFeedCopy,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: address));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.calFeedCopied)));
              }
            },
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.scheme.error),
            onPressed: () => _confirmRevoke(context, ref),
            child: Text(l.calFeedRevoke),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final l = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.calFeedRevoke),
        content: Text(l.calFeedRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.calFeedRevoke),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(manageCalendarsViewModelProvider.notifier)
          .deleteFeed(feed);
    }
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: HiwiskiMetrics.dotMedium,
    height: HiwiskiMetrics.dotMedium,
    decoration: BoxDecoration(color: color, shape: .circle),
  );
}
