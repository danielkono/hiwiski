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
import '../../features/wiki/mindmap/view/mindmap_screen.dart';
import '../../features/wiki/page/view/page_preview.dart';
import '../theme/hiwiski_metrics.dart';
import '../common/wire.dart';
import 'leave_for_target.dart';
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
///
/// [leave] closes a screen outside the app's frame first — see [LeaveForTarget],
/// which gives it otherwise.
Future<void> openLinkTarget(
  BuildContext context,
  WidgetRef ref,
  LinkItem target, {
  VoidCallback? leave,
}) {
  // The page's context, not the sheet's: the sheet is closed before the jump, and
  // its context goes with it.
  final page = Navigator.of(context, rootNavigator: true).context;
  // The navigator the preview goes on. On a phone that is the shell's, not the root:
  // closing only the root's popups left the preview open under the target, and "Back"
  // from there showed it again.
  final host = Navigator.of(context);
  final away = leave ?? LeaveForTarget.of(context);
  final body = ItemPreview(itemType: target.itemType, itemId: target.itemId);
  return showLinkPreview(
    context,
    target: target,
    // A link inside the preview leads out of the same screen.
    body: away == null ? body : LeaveForTarget(leave: away, child: body),
    onOpenFull: () {
      host.popUntil((route) => route is! PopupRoute);
      Navigator.of(page).popUntil((route) => route is! PopupRoute);
      away?.call();
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

/// An item as a link's preview shows it — its page without the info bar. Also what a
/// mind map's link element shows when it shows its target's content: the same view
/// of an item in both places.
class ItemPreview extends StatelessWidget {
  const ItemPreview({super.key, required this.itemType, required this.itemId});

  final String itemType;
  final String itemId;

  @override
  Widget build(BuildContext context) => switch (itemType) {
    EntityTypes.wikiPage => PagePreview(pageId: itemId),
    EntityTypes.todo => TodoBody(todoId: itemId, preview: true),
    EntityTypes.todoList => TodoListBody(listId: itemId),
    EntityTypes.event => EventBody(eventId: itemId),
    _ => const SizedBox.shrink(),
  };
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

/// Opens a page's mind map full screen, growing out of [from] — the global rect of
/// the preview it was opened from — as a picture grows out of its card, and shrinking
/// back into it when closed.
///
/// A route of its own over everything, not the shell's: the canvas takes the whole
/// screen. The screen is laid out at its full size from the first frame and only
/// shown through the growing frame, so the canvas fits the map once, to the screen.
Future<void> openMindmap(
  BuildContext context, {
  required String pageId,
  required Rect from,
}) => Navigator.of(context, rootNavigator: true).push(
  PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, _, _) => MindmapScreen(pageId: pageId),
    transitionsBuilder: (context, animation, _, child) => _GrowFrom(
      from: from,
      animation: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInOutCubic.flipped,
      ),
      child: child,
    ),
  ),
);

/// The screen seen through a frame that grows from [from] to the whole screen.
class _GrowFrom extends StatelessWidget {
  const _GrowFrom({
    required this.from,
    required this.animation,
    required this.child,
  });

  final Rect from;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        if (t >= 1) return child ?? const SizedBox.shrink();
        final frame = Rect.lerp(from, screen, t) ?? screen;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: frame,
              child: ClipRRect(
                borderRadius: .circular(HiwiskiMetrics.radiusCard * (1 - t)),
                child: FittedBox(
                  fit: .cover,
                  child: SizedBox.fromSize(size: screen.size, child: child),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The jump into the view of an occurrence.
void openOccurrence(BuildContext context, Occurrence occurrence) => EventRoute(
  eventId: occurrence.event.id,
  at: occurrence.start.toIso8601String(),
).go(context);
