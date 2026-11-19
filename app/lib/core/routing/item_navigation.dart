import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../components/links/view/link_preview.dart';
import '../../domain/calendar/occurrence.dart';
import '../../domain/links/link_index.dart';
import '../../domain/links/link_text.dart';
import '../../features/calendar/event/view/event_body.dart';
import '../../features/todo/detail/view/todo_body.dart';
import '../../features/todo/list/view/todo_list_body.dart';
import '../../features/wiki/page/view/page_preview.dart';
import '../common/wire.dart';
import 'navigation_view_model.dart';
import 'routes.dart';

/// **A tap on a link opens its preview** — over the current page,
/// with "Open" for the full one. The preview shows the target's page as it is, without
/// its info bar.
///
/// Jumping to an item belongs here and not in the components that trigger it:
/// `core/links` knows no feature modules, and `core/routing` knows them all — it
/// assembles the screens anyway. Otherwise every screen with links would repeat the
/// same case distinction, and one of them would always be the poorer one.
Future<void> openLinkTarget(
  BuildContext context,
  WidgetRef ref,
  LinkItem target,
) {
  // The page's context, not the sheet's: the sheet is closed before the jump, and
  // its context goes with it.
  final page = Navigator.of(context, rootNavigator: true).context;
  // The navigator the preview goes on. On a phone that is the shell's, not the root:
  // closing only the root's popups left the preview open under the target, and "Back"
  // from there showed it again.
  final host = Navigator.of(context);
  return showLinkPreview(
    context,
    target: target,
    body: switch (target.itemType) {
      EntityTypes.wikiPage => PagePreview(pageId: target.itemId),
      EntityTypes.todo => TodoBody(todoId: target.itemId, preview: true),
      EntityTypes.todoList => TodoListBody(listId: target.itemId),
      EntityTypes.event => EventBody(eventId: target.itemId),
      _ => const SizedBox.shrink(),
    },
    onOpenFull: () {
      host.popUntil((route) => route is! PopupRoute);
      Navigator.of(page).popUntil((route) => route is! PopupRoute);
      // Navigation: nothing to wait for and nothing that fails.
      openItem(
        page,
        ref,
        itemType: target.itemType,
        itemId: target.itemId,
        containerId: target.containerId,
        // Pushed: "Back" on the target returns to the page the link was on.
        push: true,
      ).ignore();
    },
  );
}

/// A row inside a preview — a task in a list, a recipe in a collection — opens its own
/// preview on top, like a link would: going to its page would leave the preview behind.
void openPreviewOf(
  BuildContext context,
  WidgetRef ref, {
  required String itemType,
  required String itemId,
}) {
  final target = ref
      .read(navigationViewModelProvider)
      .resolve(UriReference(itemType, itemId));
  if (target != null) {
    // Navigation: nothing to wait for and nothing that fails.
    openLinkTarget(context, ref, target).ignore();
  }
}

/// Goes to an item's page. [push] puts it on top of the current page, so "Back"
/// returns here; otherwise the item's area replaces the stack.
Future<void> openItem(
  BuildContext context,
  WidgetRef ref, {
  required String itemType,
  required String itemId,
  String? containerId,
  bool push = false,
}) async {
  void show(GoRouteData route) {
    if (!push) return route.go(context);
    // The pushed route answers nothing here.
    route.push<void>(context).ignore();
  }

  final place = await locateMutation.run(
    ref,
    (tsx) => tsx
        .get(navigationViewModelProvider.notifier)
        .locate(itemType: itemType, itemId: itemId, containerId: containerId),
  );
  if (place == null || !context.mounted) return;
  switch (place) {
    case ItemPlace(itemType: EntityTypes.wikiPage):
      show(WikiRoute(pageId: itemId));
    case ItemPlace(itemType: EntityTypes.todoList):
      show(TodoListRoute(listId: itemId));
    case ItemPlace(itemType: EntityTypes.todo, :final listId?):
      show(TodoDetailRoute(listId: listId, todoId: itemId));
    case ItemPlace(itemType: EntityTypes.event):
      show(EventRoute(eventId: itemId));
  }
}

/// "Back" on a page a link can lead to: to the page it was opened from, if it was
/// pushed (see [openLinkTarget]); otherwise [toParent].
void goBack(BuildContext context, VoidCallback toParent) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    toParent();
  }
}

/// Whether "Back" has a page to return to — one below this screen: a target opened
/// from a link, a wiki page opened on the phone.
///
/// Asked of the screen's own route, not of the router: the router can pop as long as
/// anything lies on top, and the wiki's tree below an open page showed a back button
/// while the page was swiped away.
bool canGoBack(BuildContext context) =>
    ModalRoute.of(context)?.canPop ?? GoRouter.of(context).canPop();

/// The jump into the view of an occurrence.
void openOccurrence(BuildContext context, Occurrence occurrence) => EventRoute(
  eventId: occurrence.event.id,
  at: occurrence.start.toIso8601String(),
).go(context);
