import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/core/api/generated/export.dart';
import 'package:hiwiski/domain/access/access_rules.dart';
import 'package:hiwiski/domain/calendar/calendar_items.dart';
import 'package:hiwiski/domain/todo/list_rules.dart';
import 'package:hiwiski/domain/todo/todo_items.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/calendar/event_sheet/event_sheet_view_model.dart';
import 'package:hiwiski/features/wiki/page/page_view_model.dart';

/// Deleting or moving a container and assigning a list are the owner's; the server
/// refuses them for everyone else, so the app no longer offers them.
void main() {
  TodoList list(String owner) => .new(
    id: 'list',
    ownerId: owner,
    version: 1,
    name: 'Household',
    kind: 'STANDARD',
    colorToken: 'BLUE',
    position: 0,
    assignees: '',
    tags: '',
  );

  WikiPage page(String owner, {String? parentId}) => .new(
    id: 'page',
    ownerId: owner,
    version: 1,
    parentId: parentId,
    position: 0,
    kind: 'PAGE',
    title: 'Router',
    content: '',
    tags: '',
  );

  PageState pageState(WikiPage page, {required AccessLevel level}) => .new(
    page: page,
    pages: [page],
    level: level,
    members: const {},
    tags: const {},
    servings: null,
    me: 'ben',
  );

  test('only the owner deletes a list; a writer still may write it', () {
    expect(mayDeleteList(list('ben'), .write, 'ben'), isTrue);
    expect(mayDeleteList(list('anna'), .write, 'ben'), isFalse);
    expect(mayDeleteList(list('anna'), .check, 'anna'), isFalse);
    expect(listWritable(list('anna'), .write), isTrue);
  });

  test('nobody known yet: the action stays — the server has the last word', () {
    expect(ownsItem('anna', null), isTrue);
  });

  test('a writer moves no page and deletes no shared root page, but deletes a '
      'subpage', () {
    final root = pageState(page('anna'), level: .write);
    final sub = pageState(page('anna', parentId: 'parent'), level: .write);
    final own = pageState(page('ben'), level: .write);

    expect(root.mayMove, isFalse);
    expect(root.mayDelete, isFalse);
    expect(sub.mayMove, isFalse);
    expect(sub.mayDelete, isTrue);
    expect(own.mayMove, isTrue);
    expect(own.mayDelete, isTrue);
  });

  test('an existing event goes into another calendar only by its owner', () {
    CalendarEvent event(String owner) => .new(
      id: 'event',
      ownerId: owner,
      version: 1,
      calendarId: 'family',
      title: 'Dinner',
      timeForm: 'TIMED',
      exceptions: '',
      attendees: '',
      tags: '',
    );
    const state = EventSheetState(
      calendars: [],
      remindersSupported: false,
      me: 'ben',
    );

    expect(state.mayMove(null), isTrue);
    expect(state.mayMove(event('ben')), isTrue);
    expect(state.mayMove(event('anna')), isFalse);
  });
}
