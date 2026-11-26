import 'package:flutter/material.dart';
import 'package:hiwiski/features/account/about/view/about_screen.dart';
import 'package:hiwiski/features/account/account/view/account_screen.dart';
import 'package:hiwiski/features/account/customize/view/customize_screen.dart';
import 'package:hiwiski/features/account/home_widgets/view/home_widgets_screen.dart';
import 'package:hiwiski/features/account/my_account/view/my_account_screen.dart';
import 'package:hiwiski/features/admin/settings/view/settings_screen.dart';
import 'package:hiwiski/features/admin/trash/view/trash_screen.dart';
import 'package:hiwiski/features/archive/view/archive_screen.dart';
import 'package:hiwiski/features/board/dashboard/view/dashboard_screen.dart';
import 'package:hiwiski/features/board/kiosk/view/kiosk_screen.dart';
import 'package:hiwiski/features/board/start/view/start_screen.dart';
import 'package:hiwiski/features/calendar/event/view/event_screen.dart';
import 'package:hiwiski/features/calendar/manage_calendars/view/manage_calendars_screen.dart';
import 'package:hiwiski/features/calendar/overview/view/calendar_overview_screen.dart';
import 'package:hiwiski/features/devices/view/devices_screen.dart';
import 'package:hiwiski/features/family/view/family_screen.dart';
import 'package:hiwiski/features/manage_tags/view/manage_tags_screen.dart';
import 'package:hiwiski/features/redeem_invitation/view/redeem_invitation_screen.dart';
import 'package:hiwiski/features/search/view/search_screen.dart';
import 'package:hiwiski/features/session/access_lost/view/access_lost_screen.dart';
import 'package:hiwiski/features/session/login/view/login_screen.dart';
import 'package:hiwiski/features/session/password_change/view/password_change_screen.dart';
import 'package:hiwiski/features/session/server_address/view/server_address_screen.dart';
import 'package:hiwiski/features/setup/view/setup_screen.dart';
import 'package:hiwiski/features/todo/categories/view/categories_screen.dart';
import 'package:hiwiski/features/todo/checklist/view/checklist_screen.dart';
import 'package:hiwiski/features/todo/detail/view/todo_detail_screen.dart';
import 'package:hiwiski/features/todo/kanban/view/kanban_screen.dart';
import 'package:hiwiski/features/todo/new_todo/view/new_todo_sheet.dart';
import 'package:hiwiski/features/todo/overview/view/todo_overview_screen.dart';
import 'package:hiwiski/features/todo/shopping/view/shopping_screen.dart';
import 'package:hiwiski/features/wiki/area/view/wiki_area_screen.dart';
import 'package:hiwiski/features/wiki/pinboard/view/pinboard_screen.dart';
import 'package:hiwiski/domain/session/session_state.dart';

import 'a11y_world.dart';

/// Every screen of the app, with the session it is shown in — the wall tablet and
/// the pages before sign-in without one.
final screenCases = <String, (SessionState, Widget Function(A11yWorld))>{
  'start': (annaSession, (_) => const StartScreen()),
  'dashboard setup': (annaSession, (_) => const DashboardScreen()),
  'wall tablet': (
    signedOutSession,
    (_) => const KioskScreen(token: kioskToken),
  ),
  'calendar': (annaSession, (_) => const CalendarOverviewScreen()),
  'event': (annaSession, (w) => EventScreen(eventId: w.id('event'))),
  'manage calendars': (annaSession, (_) => const ManageCalendarsScreen()),
  'task overview': (annaSession, (_) => const TodoOverviewScreen()),
  'task list': (annaSession, (w) => ChecklistScreen(listId: w.id('list'))),
  'shopping list': (
    annaSession,
    (w) => ShoppingScreen(listId: w.id('shopping')),
  ),
  'kanban board': (annaSession, (w) => KanbanScreen(listId: w.id('kanban'))),
  'task': (annaSession, (w) => TodoDetailScreen(todoId: w.id('todo'))),
  'new task': (
    annaSession,
    (w) => Material(
      child: SingleChildScrollView(child: NewTodoBody(listId: w.id('list'))),
    ),
  ),
  'shopping categories': (annaSession, (_) => const CategoriesScreen()),
  'wiki': (annaSession, (_) => const WikiAreaScreen()),
  'wiki page': (
    annaSession,
    (w) => WikiAreaScreen(initialPageId: w.id('page')),
  ),
  'recipe': (annaSession, (w) => WikiAreaScreen(initialPageId: w.id('recipe'))),
  'pinboard page': (
    annaSession,
    (w) => WikiAreaScreen(initialPageId: w.id('pinboard')),
  ),
  'pinboard': (annaSession, (w) => PinboardScreen(pageId: w.id('pinboard'))),
  'search': (annaSession, (_) => const SearchScreen()),
  'account': (annaSession, (_) => const AccountScreen()),
  'account (not the administrator)': (benSession, (_) => const AccountScreen()),
  'account (without a server)': (localSession, (_) => const AccountScreen()),
  'account (public instance)': (
    annaPublicSession,
    (_) => const AccountScreen(),
  ),
  'my account': (annaSession, (_) => const MyAccountScreen()),
  'customize': (annaSession, (_) => const CustomizeScreen()),
  'home screen widgets': (annaSession, (_) => const HomeWidgetsScreen()),
  'about': (annaSession, (_) => const AboutScreen()),
  'family': (annaSession, (_) => const FamilyScreen()),
  'devices': (annaSession, (_) => const DevicesScreen()),
  'tags': (annaSession, (_) => const ManageTagsScreen()),
  'archive': (annaSession, (_) => const ArchiveScreen()),
  'trash': (annaSession, (_) => const TrashScreen()),
  'settings': (annaSession, (_) => const SettingsScreen()),
  'server address': (signedOutSession, (_) => const ServerAddressScreen()),
  'server address (first start)': (
    firstStartSession,
    (_) => const ServerAddressScreen(),
  ),
  'sign in': (signedOutSession, (_) => const LoginScreen()),
  'sign in (public instance)': (
    signedOutPublicSession,
    (_) => const LoginScreen(),
  ),
  'setup': (signedOutSession, (_) => const SetupScreen()),
  'redeem invitation': (
    signedOutSession,
    (_) => const RedeemInvitationScreen(initialCode: 'K7M2-QX9P'),
  ),
  'password change': (annaSession, (_) => const PasswordChangeScreen()),
  'access lost': (annaSession, (_) => const AccessLostScreen()),
};
