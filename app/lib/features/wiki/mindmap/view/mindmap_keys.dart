import 'package:flutter/widgets.dart';

/// The keys the tests find the mind map's widgets by.
abstract final class MindmapKeys {
  static const canvas = ValueKey('mindmap-canvas');
  static const edit = ValueKey('mindmap-edit');
  static const search = ValueKey('mindmap-search');
  static const searchField = ValueKey('mindmap-search-field');
  static const fit = ValueKey('mindmap-fit');
  static const picture = ValueKey('mindmap-picture');
  static const edgeTool = ValueKey('mindmap-edge-tool');
  static const snap = ValueKey('mindmap-snap');
  static const grid = ValueKey('mindmap-grid');
  static const align = ValueKey('mindmap-align');
  static const _arrange = 'mindmap-arrange-';
  static ValueKey<String> arrange(String name) => .new('$_arrange$name');
  static const hitOrder = ValueKey('mindmap-hit-order');
  static const _hitOrder = 'mindmap-hit-order-';
  static ValueKey<String> hitOrderOf(String name) => .new('$_hitOrder$name');
  static const hitDirection = ValueKey('mindmap-hit-direction');
  static const edgeStyle = ValueKey('mindmap-edge-style');
  static const _edgeStyle = 'mindmap-edge-style-';
  static ValueKey<String> edgeStyleOf(int index) => .new('$_edgeStyle$index');
  static const shapes = ValueKey('mindmap-shapes');
  static const edgeColor = ValueKey('mindmap-edge-color');
  static const searchCount = ValueKey('mindmap-search-count');
  static const searchPrevious = ValueKey('mindmap-search-previous');
  static const searchNext = ValueKey('mindmap-search-next');
  static const edgeWidth = ValueKey('mindmap-edge-width');
  static const _penShape = 'mindmap-pen-shape-';
  static ValueKey<String> penShape(String name) => .new('$_penShape$name');
  static const closeMenu = ValueKey('mindmap-close-menu');
  static const pictureWait = ValueKey('mindmap-picture-wait');
  static const conflicts = ValueKey('mindmap-conflicts');
  static const textField = ValueKey('mindmap-text-field');
  static const save = ValueKey('mindmap-save');
  static const undo = ValueKey('mindmap-undo');
  static const redo = ValueKey('mindmap-redo');
  static const pen = ValueKey('mindmap-pen');
  static const drawings = ValueKey('mindmap-drawings');
  static const eraser = ValueKey('mindmap-eraser');
  static const penColor = ValueKey('mindmap-pen-color');
  static const strokeWidth = ValueKey('mindmap-stroke-width');
  static const back = ValueKey('mindmap-back');
  static const linkView = ValueKey('mindmap-link-view');
  static const editContent = ValueKey('mindmap-edit-content');
  static const color = ValueKey('mindmap-color');
  static const textColor = ValueKey('mindmap-text-color');
  static const shape = ValueKey('mindmap-shape');
  static const textSize = ValueKey('mindmap-text-size');
  static const textAlign = ValueKey('mindmap-text-align');
  static const textFlow = ValueKey('mindmap-text-flow');
  static const _textAlign = 'mindmap-text-align-';
  static ValueKey<String> textAlignOf(String align) =>
      .new('$_textAlign$align');
  static const layerUp = ValueKey('mindmap-layer-up');
  static const layerDown = ValueKey('mindmap-layer-down');
  static const more = ValueKey('mindmap-more');
  static const delete = ValueKey('mindmap-delete');
  static const takeMine = ValueKey('mindmap-take-mine');
  static const keepTheirs = ValueKey('mindmap-keep-theirs');

  static const _tool = 'mindmap-tool-';
  static ValueKey<String> tool(String kind) => .new('$_tool$kind');

  static const _hit = 'mindmap-hit-';
  static ValueKey<String> hit(String id) => .new('$_hit$id');

  static const _penWidth = 'mindmap-pen-width-';
  static ValueKey<String> penWidth(double width) => .new('$_penWidth$width');

  static const _choice = 'mindmap-choice-';
  static ValueKey<String> choice(String value) => .new('$_choice$value');
  static const ownNumber = ValueKey('mindmap-own-number');
  static const ownApply = ValueKey('mindmap-own-apply');

  /// The week of calendars' sheet: a calendar to tick, the week, done.
  static ValueKey<String> calendar(String id) => .new('$_calendar$id');
  static const weekCurrent = ValueKey('mindmap-week-current');
  static const weekChosen = ValueKey('mindmap-week-chosen');
  static const weekPick = ValueKey('mindmap-week-pick');
  static const calendarDone = ValueKey('mindmap-calendar-done');
  static const addMenu = ValueKey('mindmap-add-menu');
  static const drawMenu = ValueKey('mindmap-draw-menu');
  static const toolsMenu = ValueKey('mindmap-tools-menu');
  static const release = ValueKey('mindmap-release');
  static const select = ValueKey('mindmap-select');
  static const lasso = ValueKey('mindmap-lasso');
  static const rectangle = ValueKey('mindmap-rectangle');
  static const layerFront = ValueKey('mindmap-layer-front');
  static const layerBack = ValueKey('mindmap-layer-back');
  static const connect = ValueKey('mindmap-connect');

  static const _swatch = 'mindmap-swatch-';
  static ValueKey<String> swatch(String color) => .new('$_swatch$color');

  static const _member = 'mindmap-member-';
  static const _calendar = 'mindmap-calendar-';
  static ValueKey<String> member(String id) => .new('$_member$id');

  static const _target = 'mindmap-connect-';
  static ValueKey<String> connectTo(String id) => .new('$_target$id');
}
