import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../app/stores.dart';
import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/common/command.dart';
import '../../../core/common/wire.dart';
import '../../../domain/access/access_rules.dart';
import '../../../domain/calendar/calendar_items.dart';
import '../../../domain/calendar/calendar_kinds.dart';
import '../../../domain/calendar/import_target.dart';
import '../../../domain/common/change.dart';
import '../../../domain/tags/tag.dart';

part 'manage_calendars_view_model.g.dart';

/// `importIcs`, run by a view: it shows the command running and reacts to how it ended.
final importIcsMutation = Mutation<IcsImportResult>(
  label: 'manageCalendarsViewModel.importIcs',
);

/// `createFeed`, run by a view: it shows the command running and reacts to how it ended.
final createFeedMutation = Mutation<String>(
  label: 'manageCalendarsViewModel.createFeed',
);

/// `createSubscription`, run by a view: it shows the command running and reacts to how it ended.
final createSubscriptionMutation = Mutation<String>(
  label: 'manageCalendarsViewModel.createSubscription',
);

/// `createCalendar`, run by a view: it shows the command running and reacts to how it ended.
final createCalendarMutation = Mutation<String>(
  label: 'manageCalendarsViewModel.createCalendar',
);

/// A calendar with the names of the ICS links it is exported through, and whether
/// the reader may delete it — its owner only.
typedef ManagedCalendar = ({
  Calendar calendar,
  List<String> feeds,
  bool deletable,
});

/// "Manage calendars": the family's calendars, the subscriptions, the
/// ICS links, how the calendar shows all-day events.
@immutable
class const ManageCalendarsState({
  /// The calendars of one's own — not those of a subscription.
  required final List<ManagedCalendar> calendars,

  /// Every calendar, the subscribed ones included.
  required final List<Calendar> all,
  required final List<CalendarSubscription> subscriptions,

  /// The ids of the subscriptions the reader may remove: their own, or one in a
  /// calendar of theirs. Removing one takes its calendar along, which is the owner's.
  final Set<String> removableSubscriptions = const {},
  required final List<CalendarFeed> feeds,
  required final bool pinnedStrip,

  /// Where the ICS links live: outside `/api`, deliberately.
  required final String serverAddress,

  /// Whether a server stands behind the calendars. Subscriptions, ICS links, the
  /// import and sharing all run there; without one they are left out.
  final bool hasServer = true,
});

@riverpod
Stream<List<Calendar>> _calendars(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchCalendars();

@riverpod
Stream<List<CalendarSubscription>> _subscriptions(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchSubscriptions();

@riverpod
Stream<List<CalendarFeed>> _feeds(Ref ref) =>
    ref.watch(calendarRepositoryProvider).watchFeeds();

@riverpod
class ManageCalendarsViewModel extends _$ManageCalendarsViewModel {
  @override
  Future<ManageCalendarsState> build() async {
    final pinnedStrip = ref.watch(
      preferencesProvider.select((p) => p.calendarPinnedStrip),
    );
    final serverAddress = ref.watch(
      sessionProvider.select((s) => s.serverAddress ?? ''),
    );
    final calendars = ref.watch(_calendarsProvider.future);
    final subscriptions = ref.watch(_subscriptionsProvider.future);
    final feedList = ref.watch(_feedsProvider.future);
    final me = ref.watch(sessionProvider.select((s) => s.member?.id));
    final all = await calendars;
    final feeds = await feedList;
    final subscribed = await subscriptions;
    return ManageCalendarsState(
      hasServer: ref.watch(sessionProvider.select((s) => s.hasServer)),
      calendars: [
        for (final calendar in all)
          if (calendar.kind != kindExternal)
            (
              calendar: calendar,
              feeds: [
                for (final feed in feeds)
                  if (tagIdsOf(feed.calendarIds).contains(calendar.id))
                    feed.name,
              ],
              deletable: ownsItem(calendar.ownerId, me),
            ),
      ],
      all: all,
      subscriptions: subscribed,
      removableSubscriptions: {
        for (final subscription in subscribed)
          if (ownsItem(subscription.ownerId, me) ||
              all.any(
                (calendar) =>
                    calendar.id == subscription.calendarId &&
                    ownsItem(calendar.ownerId, me),
              ))
            subscription.id,
      },
      feeds: feeds,
      pinnedStrip: pinnedStrip,
      serverAddress: serverAddress,
    );
  }

  Future<void> setPinnedStrip(bool pinned) =>
      ref.read(preferencesStoreProvider).setCalendarPinnedStrip(pinned);

  /// Returns the new calendar's id; its shares go out once the server knows it.
  @command
  Future<String> createCalendar({
    required String name,
    required String colorToken,
    List<String> tags = const [],
    int? defaultReminderMinutes,
    List<WriteShare> shares = const [],
  }) async {
    final access = ref.read(accessRepositoryProvider);
    final id = await ref
        .read(calendarRepositoryProvider)
        .createCalendar(
          name: name,
          colorToken: colorToken,
          tags: tags,
          defaultReminderMinutes: defaultReminderMinutes,
        );
    await access.queueShares(
      itemType: EntityTypes.calendar,
      itemId: id,
      shares: shares,
    );
    return id;
  }

  Future<void> updateCalendar(
    Calendar calendar, {
    String? name,
    String? colorToken,
    List<String>? tags,
    Change<int?>? defaultReminderMinutes,
  }) => ref
      .read(calendarRepositoryProvider)
      .updateCalendar(
        calendar,
        name: name,
        colorToken: colorToken,
        tags: tags,
        defaultReminderMinutes: defaultReminderMinutes,
      );

  @command
  Future<String> createSubscription({
    required String name,
    required String url,
    required String colorToken,
    required String syncInterval,
    required String targetKind,
  }) => ref
      .read(calendarRepositoryProvider)
      .createSubscription(
        name: name,
        url: url,
        colorToken: colorToken,
        syncInterval: syncInterval,
        targetKind: targetKind,
      );

  @command
  Future<String> createFeed({
    required String name,
    required List<String> calendarIds,
    required String contentMode,
  }) => ref
      .read(calendarRepositoryProvider)
      .createFeed(
        name: name,
        calendarIds: calendarIds,
        contentMode: contentMode,
      );

  Future<void> deleteCalendar(Calendar calendar) =>
      ref.read(calendarRepositoryProvider).deleteCalendar(calendar);

  Future<void> refreshSubscription(CalendarSubscription subscription) =>
      ref.read(calendarRepositoryProvider).refreshSubscription(subscription.id);

  Future<void> deleteSubscription(CalendarSubscription subscription) =>
      ref.read(calendarRepositoryProvider).deleteSubscription(subscription);

  Future<void> deleteFeed(CalendarFeed feed) =>
      ref.read(calendarRepositoryProvider).deleteFeed(feed);

  @command
  Future<IcsImportResult> importIcs(
    ImportTarget target, {
    String? ics,
    String? url,
  }) => ref
      .read(calendarRepositoryProvider)
      .importIcs(target, ics: ics, url: url);
}

/// What an address or a file holds — before anything is subscribed to or imported,
/// so nobody takes the wrong calendar. Keyed by what is checked: an answer for an
/// address typed over since is never shown.
@riverpod
class CalendarPreviewViewModel extends _$CalendarPreviewViewModel {
  @override
  Future<SubscriptionPreview> build({String? url, String? ics}) => ref
      .watch(calendarRepositoryProvider)
      .previewSubscription(url: url, ics: ics);
}
