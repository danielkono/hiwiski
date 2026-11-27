import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/home_widgets/home_widget_settings.dart';
import '../../features/account/about/view/about_screen.dart';
import '../../features/account/account/view/account_screen.dart';
import '../../features/account/customize/view/customize_screen.dart';
import '../../features/account/home_widgets/view/home_widgets_screen.dart';
import '../../features/account/my_account/view/my_account_screen.dart';
import '../../features/admin/settings/view/settings_screen.dart';
import '../../features/admin/trash/view/trash_screen.dart';
import '../../features/archive/view/archive_screen.dart';
import '../../features/board/dashboard/view/dashboard_screen.dart';
import '../../features/board/kiosk/view/kiosk_screen.dart';
import '../../features/board/start/view/start_screen.dart';
import '../../features/calendar/event/view/event_screen.dart';
import '../../features/calendar/manage_calendars/view/manage_calendars_screen.dart';
import '../../features/calendar/overview/view/calendar_overview_screen.dart';
import '../../features/devices/view/devices_screen.dart';
import '../../features/family/view/family_screen.dart';
import '../../features/manage_tags/view/manage_tags_screen.dart';
import '../../features/redeem_invitation/view/redeem_invitation_screen.dart';
import '../../features/search/view/search_screen.dart';
import '../../features/session/access_lost/view/access_lost_screen.dart';
import '../../features/session/login/view/login_screen.dart';
import '../../features/session/password_change/view/password_change_screen.dart';
import '../../features/session/server_address/view/server_address_screen.dart';
import '../../features/setup/view/setup_screen.dart';
import '../../features/todo/categories/view/categories_screen.dart';
import '../../features/todo/detail/view/todo_detail_screen.dart';
import '../../features/todo/list/view/todo_list_screen.dart';
import '../../features/todo/overview/view/todo_overview_screen.dart';
import '../../features/wiki/area/view/wiki_area_screen.dart';
import '../../features/wiki/mindmap/view/mindmap_screen.dart';
import '../shell/app_shell.dart';
import '../ui/scene_frame.dart';

part 'routes.g.dart';

/// The page of every route: a screen laid on top of another — a task over its list,
/// an event over the calendar, a wiki page over the tree on the phone — is a
/// [MaterialPage], with the platform's transition and on iOS the swipe from the edge
/// back. Everything else ([onTop] `false`) appears at once, as before: an area chosen
/// in the navigation, and the screens before sign-in.
///
/// go_router picks the page by looking for its own `MaterialApp` — since 18.0 the one
/// from `material_ui`, not the one from `flutter/material.dart` this app runs in. It
/// found none and fell back to pages without a transition for every route, and those
/// cannot be swiped back.
///
/// The screens outside the shell stay without a transition on purpose: the session
/// switches between them and the shell within a frame or two (a remembered session
/// refused), and a page sliding out still holds the shell's navigator — the one
/// coming in has the same key.
abstract class HiwiskiRouteData extends GoRouteData {
  const HiwiskiRouteData();

  /// Whether this screen lies on top of another and is swiped back to it.
  bool get onTop => true;

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    final child = build(context, state);
    final name = state.name ?? state.path;
    final restorationId = state.pageKey.value;
    return onTop
        ? MaterialPage<void>(
            key: state.pageKey,
            name: name,
            restorationId: restorationId,
            child: child,
          )
        : NoTransitionPage<void>(
            key: state.pageKey,
            name: name,
            restorationId: restorationId,
            child: child,
          );
  }
}

/// An area's start, a screen outside the shell: replaces what was there.
abstract class HiwiskiRootRouteData extends HiwiskiRouteData {
  const HiwiskiRootRouteData();

  @override
  bool get onTop => false;
}

/// Typed routes: **a typo in the path is a compile error, not an empty screen**.
///
/// The four areas live in a `ShellRoute` and **replace** the stack; everything else is
/// pushed on top. An area keeps the page it was left on — not as a stack of its own
/// (`StatefulShellRoute`) but as the address the shell remembers per area and returns
/// to; Account → Customize turns that off.

@TypedShellRoute<MainShellRoute>(
  routes: [
    TypedGoRoute<HomeRoute>(path: '/'),
    TypedGoRoute<CalendarRoute>(
      path: '/calendar',
      routes: [
        TypedGoRoute<ManageCalendarsRoute>(path: 'manage'),
        TypedGoRoute<EventRoute>(path: 'event/:eventId'),
      ],
    ),
    TypedGoRoute<TodoRoute>(
      path: '/tasks',
      routes: [
        TypedGoRoute<TodoListRoute>(
          path: 'list/:listId',
          routes: [TypedGoRoute<TodoDetailRoute>(path: 'task/:todoId')],
        ),
      ],
    ),
    TypedGoRoute<WikiRoute>(path: '/wiki'),
    TypedGoRoute<SearchRoute>(path: '/search'),
    TypedGoRoute<AccountRoute>(
      path: '/account',
      routes: [
        TypedGoRoute<MyAccountRoute>(path: 'me'),
        TypedGoRoute<FamilyRoute>(path: 'family'),
        TypedGoRoute<DevicesRoute>(path: 'devices'),
        TypedGoRoute<TagsRoute>(path: 'tags'),
        TypedGoRoute<CategoriesRoute>(path: 'categories'),
        TypedGoRoute<CustomizeRoute>(path: 'customize'),
        TypedGoRoute<HomeWidgetsRoute>(path: 'home-widgets'),
        TypedGoRoute<ArchiveRoute>(path: 'archive'),
        TypedGoRoute<TrashRoute>(path: 'trash'),
        TypedGoRoute<SettingsRoute>(path: 'settings'),
        TypedGoRoute<DashboardRoute>(path: 'dashboard'),
        TypedGoRoute<AboutRoute>(path: 'about'),
      ],
    ),
  ],
)
class MainShellRoute extends ShellRouteData {
  const MainShellRoute();

  @override
  // go_router's API: a shell route answers with its widget.
  // ignore: many_lints/avoid_returning_widgets
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) =>
      SceneFrame.isScene(context)
      ? navigator
      : AppShell(location: state.uri.path, child: navigator);
}

class HomeRoute extends HiwiskiRootRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const StartScreen();
}

class DashboardRoute extends HiwiskiRouteData with $DashboardRoute {
  const DashboardRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DashboardScreen();
}

class CalendarRoute extends HiwiskiRootRouteData with $CalendarRoute {
  const CalendarRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CalendarOverviewScreen();
}

class ManageCalendarsRoute extends HiwiskiRouteData with $ManageCalendarsRoute {
  const ManageCalendarsRoute({this.newCalendar = false});

  /// Opens with "New calendar" — from the empty calendar, where there is none yet
  /// and an event would have nowhere to go.
  final bool newCalendar;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      ManageCalendarsScreen(newCalendar: newCalendar);
}

/// An event to read. `at` is the start of the intended occurrence of a series, as an
/// ISO timestamp — without it, the next one applies.
class EventRoute extends HiwiskiRouteData with $EventRoute {
  const EventRoute({required this.eventId, this.at});

  final String eventId;
  final String? at;

  @override
  Widget build(BuildContext context, GoRouterState state) => EventScreen(
    eventId: eventId,
    at: switch (at) {
      null => null,
      final at => DateTime.tryParse(at),
    },
  );
}

class TodoRoute extends HiwiskiRootRouteData with $TodoRoute {
  const TodoRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const TodoOverviewScreen();
}

class TodoListRoute extends HiwiskiRouteData with $TodoListRoute {
  const TodoListRoute({required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      TodoListScreen(listId: listId);
}

class TodoDetailRoute extends HiwiskiRouteData with $TodoDetailRoute {
  const TodoDetailRoute({required this.listId, required this.todoId});

  final String listId;
  final String todoId;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      TodoDetailScreen(todoId: todoId);
}

class SearchRoute extends HiwiskiRootRouteData with $SearchRoute {
  const SearchRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SearchScreen();
}

class WikiRoute extends HiwiskiRouteData with $WikiRoute {
  const WikiRoute({this.pageId});

  /// The page that should be open — as a query parameter, not as a path segment.
  ///
  /// The area is `/wiki`, with or without an open page: on desktop the tree sits next
  /// to it and the page is a selection in it, not a place of its own. The parameter is
  /// needed for the **jump** — from a link chip or from search.
  final String? pageId;

  /// The query parameter the generated route writes [pageId] into.
  static const _pageIdParameter = 'page-id';

  /// The page an address of the wiki holds open — `null` for another address or none.
  static String? pageIdOf(Uri uri) => uri.path == const WikiRoute().location
      ? uri.queryParameters[_pageIdParameter]
      : null;

  /// On the phone a page is pushed onto the tree; the tree itself is the area's start.
  @override
  bool get onTop => pageId != null;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      WikiAreaScreen(initialPageId: pageId);
}

class AccountRoute extends HiwiskiRootRouteData with $AccountRoute {
  const AccountRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AccountScreen();
}

class MyAccountRoute extends HiwiskiRouteData with $MyAccountRoute {
  const MyAccountRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const MyAccountScreen();
}

class FamilyRoute extends HiwiskiRouteData with $FamilyRoute {
  const FamilyRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const FamilyScreen();
}

class DevicesRoute extends HiwiskiRouteData with $DevicesRoute {
  const DevicesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const DevicesScreen();
}

class TagsRoute extends HiwiskiRouteData with $TagsRoute {
  const TagsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const ManageTagsScreen();
}

/// The shopping list's categories and which product is in which.
class CategoriesRoute extends HiwiskiRouteData with $CategoriesRoute {
  const CategoriesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CategoriesScreen();
}

/// How the app behaves on this device.
class CustomizeRoute extends HiwiskiRouteData with $CustomizeRoute {
  const CustomizeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const CustomizeScreen();
}

/// What the home screen widgets of this device show.
///
/// A widget not set up yet opens this address with its kind, and a set-up one the calendar
/// or its list: the native widgets write the app's own addresses into their links
/// (`hiwiski://widget/<address>`), which Flutter hands the router as they are — a page of
/// their own would be a second set of addresses to keep in step.
class HomeWidgetsRoute extends HiwiskiRouteData with $HomeWidgetsRoute {
  const HomeWidgetsRoute({this.kind});

  /// The widget whose settings open at once — a tap on a widget not set up yet.
  final String? kind;

  @override
  Widget build(BuildContext context, GoRouterState state) => HomeWidgetsScreen(
    open: HomeWidgetKind.values
        .where((value) => value.name == kind)
        .firstOrNull,
  );
}

/// The archive, next to the trash.
class ArchiveRoute extends HiwiskiRouteData with $ArchiveRoute {
  const ArchiveRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const ArchiveScreen();
}

class TrashRoute extends HiwiskiRouteData with $TrashRoute {
  const TrashRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const TrashScreen();
}

/// What the app is, its version and the licenses — for every member.
class AboutRoute extends HiwiskiRouteData with $AboutRoute {
  const AboutRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AboutScreen();
}

class SettingsRoute extends HiwiskiRouteData with $SettingsRoute {
  const SettingsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SettingsScreen();
}

// --- Before sign-in. Without a shell: there is nothing to navigate yet. ---

@TypedGoRoute<ServerAddressRoute>(path: '/server')
class ServerAddressRoute extends HiwiskiRootRouteData with $ServerAddressRoute {
  const ServerAddressRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const ServerAddressScreen();
}

@TypedGoRoute<SetupRoute>(path: '/setup')
class SetupRoute extends HiwiskiRootRouteData with $SetupRoute {
  const SetupRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const SetupScreen();
}

@TypedGoRoute<LoginRoute>(path: '/sign-in')
class LoginRoute extends HiwiskiRootRouteData with $LoginRoute {
  const LoginRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const LoginScreen();
}

/// The lock screen: this device lost its access, its data is kept locked.
@TypedGoRoute<AccessLostRoute>(path: '/access-lost')
class AccessLostRoute extends HiwiskiRootRouteData with $AccessLostRoute {
  const AccessLostRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const AccessLostScreen();
}

@TypedGoRoute<RedeemInvitationRoute>(path: '/invitation')
class RedeemInvitationRoute extends HiwiskiRootRouteData
    with $RedeemInvitationRoute {
  const RedeemInvitationRoute({this.code});

  /// Comes from the deep link `hiwiski://invite?host=…&code=…`.
  final String? code;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      RedeemInvitationScreen(initialCode: code);
}

/// The wall tablet board: `…/board/<token>`.
///
/// **Without sign-in and without a shell** — no navigation, no header, no way into the
/// app. That is why the route lives outside the `ShellRoute`, and the router lets
/// it through without a session.
@TypedGoRoute<KioskRoute>(path: '/board/:token')
class KioskRoute extends HiwiskiRootRouteData with $KioskRoute {
  const KioskRoute({required this.token});

  final String token;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      KioskScreen(token: token);
}

/// A wiki page's mind map, full screen: the canvas to move around on, search and —
/// for whoever may write the page — edit. Outside the shell, so the canvas has the
/// whole screen; pushed over the page it came from, which "Back" returns to.
///
/// [node] is an element (or connection) to show and mark — a search hit, a conflict
/// from the banner.
@TypedGoRoute<MindmapRoute>(path: '/mindmap/:pageId')
class MindmapRoute extends HiwiskiRouteData with $MindmapRoute {
  const MindmapRoute({required this.pageId, this.node});

  final String pageId;
  final String? node;

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      MindmapScreen(pageId: pageId, focus: node);
}

/// **Not a screen you call up, but one you get stuck on**: no cancel,
/// no back, no navigation.
@TypedGoRoute<PasswordChangeRoute>(path: '/password')
class PasswordChangeRoute extends HiwiskiRootRouteData
    with $PasswordChangeRoute {
  const PasswordChangeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      const PasswordChangeScreen();
}
