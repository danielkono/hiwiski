import 'package:flutter/widgets.dart';

/// The keys the tests find the pinboard's widgets by.
abstract final class PinboardKeys {
  static const canvas = ValueKey('pinboard-canvas');
  static const edit = ValueKey('pinboard-edit');
  static const search = ValueKey('pinboard-search');
  static const searchField = ValueKey('pinboard-search-field');
  static const fit = ValueKey('pinboard-fit');
  static const picture = ValueKey('pinboard-picture');
  static const edgeTool = ValueKey('pinboard-edge-tool');
  static const snap = ValueKey('pinboard-snap');
  static const grid = ValueKey('pinboard-grid');
  static const align = ValueKey('pinboard-align');
  static const _arrange = 'pinboard-arrange-';
  static ValueKey<String> arrange(String name) => .new('$_arrange$name');
  static const hitOrder = ValueKey('pinboard-hit-order');
  static const _hitOrder = 'pinboard-hit-order-';
  static ValueKey<String> hitOrderOf(String name) => .new('$_hitOrder$name');
  static const hitDirection = ValueKey('pinboard-hit-direction');
  static const edgeStyle = ValueKey('pinboard-edge-style');
  static const _edgeStyle = 'pinboard-edge-style-';
  static ValueKey<String> edgeStyleOf(int index) => .new('$_edgeStyle$index');
  static const shapes = ValueKey('pinboard-shapes');
  static const edgeColor = ValueKey('pinboard-edge-color');
  static const searchCount = ValueKey('pinboard-search-count');
  static const searchPrevious = ValueKey('pinboard-search-previous');
  static const searchNext = ValueKey('pinboard-search-next');
  static const edgeWidth = ValueKey('pinboard-edge-width');
  static const _penShape = 'pinboard-pen-shape-';
  static ValueKey<String> penShape(String name) => .new('$_penShape$name');
  static const closeMenu = ValueKey('pinboard-close-menu');
  static const pictureWait = ValueKey('pinboard-picture-wait');
  static const conflicts = ValueKey('pinboard-conflicts');
  static const textField = ValueKey('pinboard-text-field');
  static const save = ValueKey('pinboard-save');
  static const undo = ValueKey('pinboard-undo');
  static const redo = ValueKey('pinboard-redo');
  static const pen = ValueKey('pinboard-pen');
  static const drawings = ValueKey('pinboard-drawings');
  static const eraser = ValueKey('pinboard-eraser');
  static const penColor = ValueKey('pinboard-pen-color');
  static const strokeWidth = ValueKey('pinboard-stroke-width');
  static const back = ValueKey('pinboard-back');
  static const linkView = ValueKey('pinboard-link-view');
  static const editContent = ValueKey('pinboard-edit-content');
  static const color = ValueKey('pinboard-color');
  static const textColor = ValueKey('pinboard-text-color');
  static const shape = ValueKey('pinboard-shape');
  static const textSize = ValueKey('pinboard-text-size');
  static const textAlign = ValueKey('pinboard-text-align');
  static const textFlow = ValueKey('pinboard-text-flow');
  static const _textAlign = 'pinboard-text-align-';
  static ValueKey<String> textAlignOf(String align) =>
      .new('$_textAlign$align');
  static const layerUp = ValueKey('pinboard-layer-up');
  static const layerDown = ValueKey('pinboard-layer-down');
  static const more = ValueKey('pinboard-more');
  static const delete = ValueKey('pinboard-delete');
  static const takeMine = ValueKey('pinboard-take-mine');
  static const keepTheirs = ValueKey('pinboard-keep-theirs');

  static const _tool = 'pinboard-tool-';
  static ValueKey<String> tool(String kind) => .new('$_tool$kind');

  static const _hit = 'pinboard-hit-';
  static ValueKey<String> hit(String id) => .new('$_hit$id');

  static const _penWidth = 'pinboard-pen-width-';
  static ValueKey<String> penWidth(double width) => .new('$_penWidth$width');

  static const _choice = 'pinboard-choice-';
  static ValueKey<String> choice(String value) => .new('$_choice$value');
  static const ownNumber = ValueKey('pinboard-own-number');
  static const ownApply = ValueKey('pinboard-own-apply');

  /// The week of calendars' sheet: a calendar to tick, the week, done.
  static ValueKey<String> calendar(String id) => .new('$_calendar$id');
  static const weekCurrent = ValueKey('pinboard-week-current');
  static const weekChosen = ValueKey('pinboard-week-chosen');
  static const weekPick = ValueKey('pinboard-week-pick');
  static const calendarDone = ValueKey('pinboard-calendar-done');
  static const addMenu = ValueKey('pinboard-add-menu');
  static const drawMenu = ValueKey('pinboard-draw-menu');
  static const toolsMenu = ValueKey('pinboard-tools-menu');
  static const release = ValueKey('pinboard-release');
  static const select = ValueKey('pinboard-select');
  static const lasso = ValueKey('pinboard-lasso');
  static const rectangle = ValueKey('pinboard-rectangle');
  static const layerFront = ValueKey('pinboard-layer-front');
  static const layerBack = ValueKey('pinboard-layer-back');
  static const connect = ValueKey('pinboard-connect');

  static const _swatch = 'pinboard-swatch-';
  static ValueKey<String> swatch(String color) => .new('$_swatch$color');

  static const _member = 'pinboard-member-';
  static const _calendar = 'pinboard-calendar-';
  static ValueKey<String> member(String id) => .new('$_member$id');

  static const _target = 'pinboard-connect-';
  static ValueKey<String> connectTo(String id) => .new('$_target$id');
}
