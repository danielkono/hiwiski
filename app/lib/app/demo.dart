import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset, PlatformDispatcher;

import 'package:clock/clock.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/image_client.dart';
import '../core/common/wire.dart';
import '../core/theme/hiwiski_metrics.dart';
import '../domain/board/widget_kinds.dart';
import '../domain/calendar/event_draft.dart';
import '../domain/links/link_text.dart';
import '../domain/todo/kanban.dart';
import '../domain/wiki/pinboard.dart';
import '../domain/wiki/page_images.dart';
import '../domain/wiki/wiki_models.dart';
import 'repositories.dart';
import 'stores.dart';

/// The public demo: the app without a server, on sample data, keeping
/// nothing. Every page load — and every "Reset" — starts from the same family.
///
/// The sample data is an asset per language (`assets/demo/demo-<language>.json`),
/// not code: it is data, and a translation is another file. It is written through
/// the repositories, the way a member's own input is, so the demo shows what the
/// app does and not what a seed made up.
class Demo {
  Demo(this._ref);

  final Ref _ref;

  /// The start under way, if any — one at a time.
  Future<void>? _starting;

  /// The language of the sample data, when the page decides it rather than the
  /// browser — a scene on the website.
  String? _language;

  static const _languages = {'de', 'en'};
  static const _fallback = 'en';
  static const _asset = 'assets/demo/demo-';
  static const _extension = '.json';

  // The keys of the sample data.
  static const _me = 'me';
  static const _family = 'family';
  static const _tags = 'tags';
  static const _lists = 'lists';
  static const _calendars = 'calendars';
  static const _pages = 'pages';
  static const _start = 'start';
  static const _key = 'key';
  static const _name = 'name';
  static const _title = 'title';
  static const _color = 'color';
  static const _kind = 'kind';
  static const _items = 'items';
  static const _events = 'events';
  static const _amount = 'amount';
  static const _unit = 'unit';
  static const _due = 'due';
  static const _rrule = 'rrule';
  static const _assignees = 'assignees';
  static const _attendees = 'attendees';
  static const _day = 'day';
  static const _weekday = 'weekday';
  static const _date = 'date';
  static const _days = 'days';
  static const _startTime = 'start';
  static const _endTime = 'end';
  static const _allDay = 'allDay';
  static const _location = 'location';
  static const _content = 'content';
  static const _servings = 'servings';
  static const _duration = 'durationMinutes';
  static const _ingredients = 'ingredients';
  static const _children = 'children';
  static const _columns = 'columns';
  static const _column = 'column';
  static const _done = 'done';
  static const _description = 'description';
  static const _linkKey = 'key';
  static const _pageLink = 'page:';
  static const _listLink = 'list:';
  static const _pinboard = 'pinboard';
  static const _nodes = 'nodes';
  static const _edges = 'edges';
  static const _x = 'x';
  static const _y = 'y';
  static const _width = 'width';
  static const _height = 'height';
  static const _words = 'text';
  static const _look = 'look';
  static const _image = 'image';
  static const _target = 'target';
  static const _member = 'member';
  static const _points = 'points';
  static const _pen = 'pen';
  static const _from = 'from';
  static const _to = 'to';
  static const _images = 'assets/demo/images/';
  static const _imageExtension = '.jpg';

  /// `{{page:recipes}}`, `{{list:shopping}}`: a link to what the sample data
  /// names by that key — written as the link picker writes it, once the target
  /// exists and has an id.
  static final _placeholder = RegExp(r'\{\{((?:page|list):[a-z0-9-]+)\}\}');

  /// What a placeholder points to, by `page:<key>` and `list:<key>`.
  final _targets = <String, ({String type, String id, String title})>{};
  static const _timeSeparator = ':';
  static const _dateSeparator = '-';

  /// The demo's family and its sample data — once per page load. [language] picks
  /// the sample data instead of the browser's language.
  Future<void> start({String? language}) {
    _language ??= language;
    return _starting ??= _seed();
  }

  /// The language the page chose for the sample data, if it chose one.
  String? get language => _language;

  /// The id of what the sample data names by [key] — `page:<key>` or `list:<key>` —
  /// once the demo has started; `null` for a key it does not hold.
  String? idOf(String key) => _targets[key]?.id;

  /// Everything made in the demo goes, and it begins anew.
  Future<void> reset() async {
    await _starting;
    await _ref.read(sessionStoreProvider).clearLocalData();
    _starting = null;
    _targets.clear();
    await start();
  }

  Future<void> _seed() async {
    final data = jsonDecode(
      await rootBundle.loadString(_assetPath(_language)),
    ) as Map<String, dynamic>;
    final session = _ref.read(sessionStoreProvider);
    await session.beginDemo(_text(data, _me));
    final me = session.value.member?.id;
    if (me == null) return;

    // The family by its place in the sample data: 0 is the demo's own member.
    final family = <String>[me];
    for (final member in _list(data[_family])) {
      family.add(
        await _ref
            .read(familyRepositoryProvider)
            .addLocalMember(_text(member, _name), _text(member, _color)),
      );
    }
    List<String> members(Object? indices) => [
      for (final index in (indices as List<dynamic>? ?? const []).cast<int>())
        if (index < family.length) family[index],
    ];

    final tagIds = <String, String>{};
    for (final tag in _list(data[_tags])) {
      tagIds[_text(tag, _key)] = await _ref
          .read(tagRepositoryProvider)
          .createTag(_text(tag, _name), colorToken: _text(tag, _color));
    }
    List<String> tags(Object? keys) => [
      for (final key in (keys as List<dynamic>? ?? const []).cast<String>())
        ?tagIds[key],
    ];

    await _seedLists(data, members, tags);
    await _seedCalendars(data, members, tags);
    await _seedPages(data, members, tags);
    await _seedStartBoard(data);
  }

  Future<void> _seedLists(
    Map<String, dynamic> data,
    List<String> Function(Object?) members,
    List<String> Function(Object?) tags,
  ) async {
    final todos = _ref.read(todoRepositoryProvider);
    final today = _today();
    for (final list in _list(data[_lists])) {
      // A board's columns, in order; a card names its column by its place.
      final columns = [
        for (final column in _list(list[_columns]))
          KanbanColumn.create(
            _text(column, _name),
            colorToken: column[_color] as String? ?? ColorTokens.blue,
            done: column[_done] == true,
          ),
      ];
      final listId = await todos.createList(
        name: _text(list, _name),
        kind: _text(list, _kind),
        description: list[_description] as String?,
        colorToken: list[_color] as String? ?? ColorTokens.blue,
        columns: columns.isEmpty ? null : columns,
        tags: tags(list[_tags]),
      );
      if (list[_linkKey] case final String key) {
        _targets['$_listLink$key'] = (
          type: EntityTypes.todoList,
          id: listId,
          title: _text(list, _name),
        );
      }
      for (final item in _list(list[_items])) {
        final id = await todos.createTodo(
          listId: listId,
          title: _text(item, _title),
          description: item[_description] as String?,
          amount: (item[_amount] as num?)?.toDouble(),
          unit: item[_unit] as String?,
          dueDate: switch (item[_due]) {
            final int days => DateTime(
              today.year,
              today.month,
              today.day + days,
            ),
            _ => null,
          },
          rrule: item[_rrule] as String?,
          assignees: members(item[_assignees]),
          tags: tags(item[_tags]),
          columnId: switch (item[_column]) {
            final int index when index < columns.length => columns[index].id,
            _ => null,
          },
        );
        if (item[_done] == true) {
          final todo = await todos.watchTodo(id).firstWhere((t) => t != null);
          if (todo != null) await todos.setStatus(todo, true);
        }
      }
    }
  }

  Future<void> _seedCalendars(
    Map<String, dynamic> data,
    List<String> Function(Object?) members,
    List<String> Function(Object?) tags,
  ) async {
    final calendar = _ref.read(calendarRepositoryProvider);
    final today = _today();
    for (final entry in _list(data[_calendars])) {
      final calendarId = await calendar.createCalendar(
        name: _text(entry, _name),
        colorToken: _text(entry, _color),
      );
      for (final event in _list(entry[_events])) {
        final day = _dayOf(event, today);
        final rrule = event[_rrule] as String?;
        DateTime start() => _at(day, _text(event, _startTime));
        DateTime end() => _at(day, _text(event, _endTime));
        await calendar.createEvent(
          calendarId: calendarId,
          draft: EventDraft(
            title: _text(event, _title),
            // A series with a time is stored on the wall clock, as the editor stores
            // it. As a moment with a rule it showed only once, on its first day, and
            // a drag moved the whole series without asking.
            time: switch ((event[_allDay] == true, rrule != null)) {
              (true, _) => AllDayEvent(
                day,
                DateTime(
                  day.year,
                  day.month,
                  day.day + (event[_days] as int? ?? 1) - 1,
                ),
              ),
              (false, true) => RecurringEvent(start(), end()),
              (false, false) => TimedEvent(start(), end()),
            },
            location: event[_location] as String?,
            rrule: rrule,
            attendees: members(event[_attendees]),
            tags: tags(event[_tags]),
          ),
        );
      }
    }
  }

  /// All pages first, then their texts and pinboards: a text links to pages further
  /// down.
  Future<void> _seedPages(
    Map<String, dynamic> data,
    List<String> Function(Object?) members,
    List<String> Function(Object?) tags,
  ) async {
    final created = <(String, Map<String, dynamic>)>[];
    await _createPagesUnder(_list(data[_pages]), null, created);
    final wiki = _ref.read(wikiRepositoryProvider);
    for (final (id, entry) in created) {
      final page = await wiki.watchPage(id).firstWhere((page) => page != null);
      if (page == null) continue;
      await wiki.updatePage(
        page,
        content: switch (entry[_content]) {
          final String content => _resolveLinks(content),
          _ => null,
        },
        tags: switch (tags(entry[_tags])) {
          final List<String> ids when ids.isNotEmpty => ids,
          _ => null,
        },
        properties: {
          if (entry[_servings] case final int servings)
            WireFields.servings: servings,
          if (entry[_duration] case final int minutes)
            WireFields.durationMinutes: minutes,
          if (entry[_ingredients] case final List<dynamic> ingredients)
            WireFields.ingredients: [
              for (final item in ingredients.cast<Map<String, dynamic>>())
                Ingredient.fromJson(item).toJson(),
            ],
        },
      );
      if (entry[_pinboard] case final Map<String, dynamic> map) {
        await _seedPinboard(id, map, members);
      }
    }
  }

  /// The elements of a pinboard, in the order they lie on each other, and then their
  /// connections — placed as the map's screen places them. An element names what it
  /// shows by the sample data's own words: a picture by its file in
  /// `assets/demo/images/`, a link by `page:<key>` or `list:<key>`, a member by their
  /// place in the family; a stroke by its points on the map, or a shape the pen draws
  /// by its two corners.
  Future<void> _seedPinboard(
    String pageId,
    Map<String, dynamic> map,
    List<String> Function(Object?) members,
  ) async {
    final maps = _ref.read(pinboardRepositoryProvider);
    final media = _ref.read(mediaRepositoryProvider);
    final ids = <String, String>{};
    for (final node in _list(map[_nodes])) {
      final kind = _text(node, _kind);
      final look = <String, Object?>{...?node[_look] as Map<String, dynamic>?};
      String text = _text(node, _words);
      int x = node[_x] as int? ?? 0, y = node[_y] as int? ?? 0;
      int width = node[_width] as int? ?? 0,
          height = node[_height] as int? ?? 0;
      if (node[_image] case final String file) {
        final bytes = await rootBundle.load('$_images$file$_imageExtension');
        // Kept on the device, as a picture placed on the map is: the demo has no
        // server to take it.
        final imageId = await media.keep(
          ownerType: ImageOwnerTypes.wikiPage,
          ownerItemId: pageId,
          bytes: bytes.buffer.asUint8List(),
          filename: '$file$_imageExtension',
        );
        text = imageMarkdown(imageId, name: text);
      }
      if (_targets[node[_target]] case final target?) {
        look[WireFields.target] = linkAddressOf(
          UriReference.markdown(target.type, target.id, target.title),
        );
      }
      if (node[_member] case final int index) {
        if (members([index]).firstOrNull case final member?) {
          look[WireFields.target] = memberAddressOf(member);
        }
      }
      if (node[_points] case final List<dynamic> given) {
        final strokeWidth = look[WireFields.strokeWidth] as int? ?? 1;
        final points = [
          for (final point in given.cast<List<dynamic>>())
            Offset((point[0] as num).toDouble(), (point[1] as num).toDouble()),
        ];
        final pen = PinboardPenShape.values
            .where((shape) => penShapeName(shape) == node[_pen])
            .firstOrNull;
        // As the pen draws it: a shape along its outline, as thick as on the screen.
        final stroke = strokeOf(
          pen == null || points.length < 2
              ? points
              : penShapeOutline(
                  pen,
                  points.first,
                  points.last,
                  head: penArrowHead(
                    strokeWidth.toDouble(),
                    least: HiwiskiMetrics.pinboardArrowHead * 2,
                  ),
                ),
          strokeWidth.toDouble(),
        );
        x = stroke.bounds.left.round();
        y = stroke.bounds.top.round();
        width = math.max(1, stroke.bounds.width.round());
        height = math.max(1, stroke.bounds.height.round());
        look[WireFields.points] = stroke.points;
        look[WireFields.shape] = pen == null ? null : penShapeName(pen);
      }
      final id = await maps.addNode(
        pageId: pageId,
        kind: kind,
        x: x,
        y: y,
        width: width,
        height: height,
        text: text,
        look: look,
      );
      if (node[_linkKey] case final String key) ids[key] = id;
    }
    for (final edge in _list(map[_edges])) {
      final from = await maps.node(ids[edge[_from]] ?? '');
      final to = await maps.node(ids[edge[_to]] ?? '');
      if (from == null || to == null) continue;
      await maps.connect(
        from,
        to,
        text: _text(edge, _words),
        look: {...?edge[_look] as Map<String, dynamic>?},
      );
    }
  }

  /// [entries] under [parentId], and each one's `children` under it — into
  /// [created], in order.
  Future<void> _createPagesUnder(
    List<Map<String, dynamic>> entries,
    String? parentId,
    List<(String, Map<String, dynamic>)> created,
  ) async {
    final wiki = _ref.read(wikiRepositoryProvider);
    for (final entry in entries) {
      final title = _text(entry, _title);
      final id = await wiki.createPage(
        title: title,
        parentId: parentId,
        kind: entry[_kind] as String? ?? PageKinds.page,
      );
      if (entry[_linkKey] case final String key) {
        _targets['$_pageLink$key'] = (
          type: EntityTypes.wikiPage,
          id: id,
          title: title,
        );
      }
      created.add((id, entry));
      await _createPagesUnder(_list(entry[_children]), id, created);
    }
  }

  /// The placeholders of [content] as links; one without a target stays as it is.
  String _resolveLinks(String content) =>
      content.replaceAllMapped(_placeholder, (match) {
        final target = _targets[match[1]];
        return target == null
            ? match[0] ?? ''
            : UriReference.markdown(target.type, target.id, target.title);
      });

  Future<void> _seedStartBoard(Map<String, dynamic> data) async {
    final boards = _ref.read(boardRepositoryProvider);
    final board = await boards.ensure(BoardKinds.start);
    for (final kind
        in (data[_start] as List<dynamic>? ?? const []).cast<String>()) {
      // Only tiles this app knows — the sample data names them by their ids.
      if (!WidgetKind.all.any((known) => known.id == kind)) continue;
      await boards.addWidget(
        board: board,
        kind: kind,
        existing: await boards.watchWidgets(board.id).first,
      );
    }
  }

  /// A text of the sample data — empty where it is missing, rather than a throw
  /// halfway through the seed.
  static String _text(Map<String, dynamic> entry, String key) =>
      entry[key] as String? ?? '';

  static List<Map<String, dynamic>> _list(Object? value) =>
      (value as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

  static DateTime _today() {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The day an event of the sample data starts on — relative to [today], so the
  /// demo looks the same whenever it is opened:
  ///
  /// - `date`: `MM-DD`, the next such day from today on — birthdays, holidays;
  /// - `weekday`: 1 (Monday) to 7, the next such weekday from today on — a weekly
  ///   series starts on a day its rule holds;
  /// - `day`: that many days from today.
  static DateTime _dayOf(Map<String, dynamic> event, DateTime today) {
    if (event[_date] case final String date) {
      final [month, day] = date.split(_dateSeparator).map(int.parse).toList();
      final thisYear = DateTime(today.year, month, day);
      return thisYear.isBefore(today)
          ? DateTime(today.year + 1, month, day)
          : thisYear;
    }
    if (event[_weekday] case final int weekday) {
      return DateTime(
        today.year,
        today.month,
        today.day + (weekday - today.weekday) % DateTime.daysPerWeek,
      );
    }
    return DateTime(
      today.year,
      today.month,
      today.day + (event[_day] as int? ?? 0),
    );
  }

  /// [day] at `HH:MM`.
  static DateTime _at(DateTime day, String time) {
    final [hours, minutes] = time.split(_timeSeparator).map(int.parse).toList();
    return DateTime(day.year, day.month, day.day, hours, minutes);
  }

  static String _assetPath(String? chosen) {
    final language = chosen ?? PlatformDispatcher.instance.locale.languageCode;
    return '$_asset${_languages.contains(language) ? language : _fallback}'
        '$_extension';
  }
}
