import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../components/links/view/link_picker.dart';
import '../../../../components/rich_text/view/image_files.dart';
import '../../../../components/rich_text/view/image_gallery.dart';
import '../../../../components/sync_banner/view/sync_banner.dart';
import '../../../../core/api/generated/export.dart';
import '../../../../core/common/wire.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/item_navigation.dart';
import '../../../../core/routing/leave_for_target.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/theme/mindmap_colors.dart';
import '../../../../core/ui/archive_files.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/states.dart';
import '../../../../domain/sync/sync_items.dart';
import '../../../../domain/transfer/transfer_bundle.dart';
import '../../../../domain/wiki/mindmap.dart';
import '../../../../domain/wiki/mindmap_snap.dart';
import '../../view/mindmap/mindmap_members.dart';
import '../../view/mindmap/mindmap_picture.dart';
import '../../view/mindmap/mindmap_scene.dart';
import '../mindmap_view_model.dart';
import 'mindmap_camera.dart';
import 'mindmap_canvas.dart';
import 'mindmap_color_sheet.dart';
import 'mindmap_conflict_bar.dart';
import 'mindmap_corner.dart';
import 'mindmap_keys.dart';
import 'mindmap_results.dart';
import 'mindmap_sheets.dart';

/// A page's mind map, full screen: moved around and zoomed by hand, searched, and —
/// with "Edit" — changed: elements placed from the bar, dragged, resized, connected,
/// coloured, shaped and stacked.
///
/// **A frame of its own** (like the wall tablet's board): the canvas runs under the
/// status bar, the header and the bars, and those lie over it — the header without a
/// background of its own, only its text and buttons on small surfaces, everything
/// inside the safe area.
///
/// **Every change is written at once**, as ticking off a task is: whoever else has the
/// map open sees it with the next sync, and there is no "Save" that could be forgotten
/// while others work on the same map. "Undo" takes a change back the same way; "Done"
/// only ends editing.
class MindmapScreen extends ConsumerStatefulWidget {
  const MindmapScreen({super.key, required this.pageId, this.focus});

  final String pageId;

  /// An element or connection to go to and mark when the map opens.
  final String? focus;

  @override
  ConsumerState<MindmapScreen> createState() => _MindmapScreenState();
}

class _MindmapScreenState extends ConsumerState<MindmapScreen> {
  final _camera = MindmapCamera();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _keys = FocusNode();
  bool _editing = false;
  bool _searching = false;
  int _hit = 0;
  MindmapSelection? _selection;

  /// Marked once the map opens with [MindmapScreen.focus].
  String? _marked;

  /// The element or connection whose conflict is being decided on the map.
  String? _deciding;

  /// A snippet of text being written on the canvas — new, or one already there — and
  /// what is typed into it.
  ({MindmapNode node, bool isNew})? _writing;
  final _typed = TextEditingController();
  final _typing = FocusNode();

  /// A snippet as it was just written: shown so while the map does not have it yet —
  /// [_heldFrom] still standing there, or, for a new one, no [_heldAs] yet.
  MindmapNode? _held;
  MindmapNode? _heldFrom;
  String? _heldAs;

  /// How high the keyboard stands — the snippet being written is kept above it.
  double _keyboard = 0;

  /// Strokes just drawn, shown as they will be until the map has them: let go of when
  /// the pen lifted, a stroke was gone for a moment before it came back.
  final _strokes = <MindmapNode>[];
  int _strokeCount = 0;

  /// What a finger does while editing, and what the pen draws with — its colour as
  /// stored (`null`: the theme's ink) and how thick it is on screen.
  MindmapTool _tool = .select;

  /// Whether the strokes drawn by hand are out of sight, on this screen.
  bool _drawingsHidden = false;

  /// Elements selected together by a lasso or a rectangle.
  Set<String> _group = const {};

  /// Which of the corner's menus is open — `null`: none — and a level below one of
  /// its choices.
  int? _menu;
  _Submenu? _submenu;

  /// How the connection tool draws — its kind, colour and thickness, chosen before
  /// and kept apart from the pen's — and which shape the shape tool.
  MindmapEdgeStyle _edgeStyle = mindmapEdgeStyles.first;
  String? _edgeColor;
  int? _edgeWidth;
  MindmapPenShape _penShape = .rectangle;
  String? _penColor;
  double _penWidth = HiwiskiMetrics.mindmapPenWidths[1];

  @override
  void initState() {
    super.initState();
    _typing.addListener(_focusChanged);
    _typed.addListener(_typedChanged);
  }

  /// Written until it is left: a tap elsewhere, Escape, "Done" — each takes the
  /// focus away, and what is typed is kept.
  void _focusChanged() {
    if (!_typing.hasFocus && _writing != null) unawaited(_finishWriting());
  }

  /// The snippet grows with what is typed.
  void _typedChanged() {
    final writing = _writing;
    if (writing != null) setState(() => _writing = writing);
  }

  @override
  void dispose() {
    _camera.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _keys.dispose();
    _typed
      ..removeListener(_typedChanged)
      ..dispose();
    _typing
      ..removeListener(_focusChanged)
      ..dispose();
    super.dispose();
  }

  MindmapViewModel get _viewModel =>
      ref.read(mindmapViewModelProvider(widget.pageId).notifier);

  MindmapState? get _state =>
      ref.read(mindmapViewModelProvider(widget.pageId)).value;

  /// Whether the map is being edited: switched on, and the map still writable. Every
  /// key and tap that changes something asks this, not the switch alone — a map
  /// archived or no longer shared for writing meanwhile still took a key's delete.
  bool get _editable => _editing && (_state?.writable ?? false);

  /// The map stopped being writable: editing ends, as "Done" ends it.
  void _writableChanged(bool? before, bool? writable) {
    if (writable ?? true) return;
    if (_editing) _toggleEditing();
  }

  void _back() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      WikiRoute(pageId: widget.pageId).go(context);
    }
  }

  // --- Where the camera looks ---------------------------------------------------

  void _ready() {
    final state = _state;
    if (state == null) return;
    _camera.fit(state.map.bounds);
    final focus = widget.focus;
    final target = focus == null ? null : _boundsOf(state, focus);
    if (focus == null || target == null) return;
    if (state.conflicts.containsKey(focus)) {
      // Opened from the banner for this conflict: it is decided here.
      _decideOnMap(focus);
      return;
    }
    _camera.show(target);
    setState(() => _marked = focus);
  }

  Rect? _boundsOf(MindmapState state, String id) {
    if (state.map.node(id) case final node?) return node.bounds;
    final edge = state.map.edge(id);
    if (edge == null) return null;
    final path = edgePathOf(state.map, edge, HiwiskiMetrics.mindmapEdgeSpread);
    return path == null
        ? null
        : Rect.fromPoints(path.start, path.end).inflate(HiwiskiMetrics.space32);
  }

  /// The middle of the free part of the view, as an element's top left corner of
  /// [size].
  ({int x, int y}) _middle(Size size) {
    final free = _camera.padding.deflateRect(Offset.zero & _camera.viewport);
    final centre = _camera.toScene(free.center);
    return (
      x: (centre.dx - size.width / 2).round(),
      y: (centre.dy - size.height / 2).round(),
    );
  }

  /// What lies over the canvas at its edges, for the camera to fit the map between.
  EdgeInsets _covered(
    BuildContext context, {
    required bool results,
    required bool deciding,
  }) {
    final safe = MediaQuery.paddingOf(context);
    final wide = !Breakpoint.of(context).isCompact;
    // On a phone, the way from hit to hit has a line of its own below the header.
    final steps = !wide && _searching && _search.text.trim().isNotEmpty;
    final header =
        HiwiskiMetrics.minTapTarget +
        2 * HiwiskiMetrics.space8 +
        (steps ? HiwiskiMetrics.minTapTarget : 0);
    // The conflict being decided across the foot; editing, the corner's buttons —
    // its quarter circle opens over the map and goes again.
    final bars = switch ((deciding, _editable)) {
      (true, _) => HiwiskiMetrics.mindmapConflictBarHeight,
      (false, true) => HiwiskiMetrics.fabClearance,
      (false, false) => 0.0,
    };
    return EdgeInsets.only(
      left: safe.left,
      top: safe.top + header,
      right:
          safe.right +
          (results && wide ? HiwiskiMetrics.mindmapResultsWidth : 0),
      bottom:
          safe.bottom +
          bars +
          (results && !wide ? HiwiskiMetrics.mindmapPreviewMinHeight : 0),
    );
  }

  // --- Search -------------------------------------------------------------------

  /// The hits come with the next state; the first one is shown then
  /// ([_hitsChanged]).
  void _query(String text) => _viewModel.search(text);

  void _hitsChanged(List<MindmapHit>? before, List<MindmapHit>? hits) {
    if (!_searching || hits == null || hits.isEmpty) return;
    final first = hits.first;
    if (before != null && before.isNotEmpty && before.first == first) return;
    setState(() => _hit = 0);
    _camera.show(first.bounds);
  }

  void _showHit(int index) {
    final hits = _state?.hits ?? const [];
    if (hits.isEmpty || !mounted) return;
    final at = index % hits.length;
    setState(() => _hit = at < 0 ? at + hits.length : at);
    _camera.show(hits[_hit].bounds);
  }

  void _toggleSearch() {
    if (_searching) {
      setState(() => _searching = false);
      _search.clear();
      _viewModel.search('');
      _keys.requestFocus();
    } else {
      _openSearch();
    }
  }

  /// Opens the search and puts the cursor into it — asked for by a click, ready to
  /// type. `autofocus` would not: the canvas holds the focus already.
  void _openSearch() {
    if (!_searching) setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  // --- Selecting, keys ----------------------------------------------------------

  void _select(MindmapSelection? selection) {
    setState(() {
      _selection = selection;
      _group = const {};
      _marked = null;
      if (_submenu == .align) _submenu = null;
    });
    _keys.requestFocus();
  }

  /// A lasso or a rectangle went round [ids]: they are selected together — one alone
  /// is selected as any — and the finger selects and moves again.
  void _grouped(Set<String> ids) {
    if (ids.length < 2) {
      setState(() => _tool = .select);
      _select(ids.isEmpty ? null : .node(ids.single));
      return;
    }
    setState(() {
      _group = ids;
      _selection = null;
      _tool = .select;
      if (_submenu == .align) _submenu = null;
    });
    _keys.requestFocus();
  }

  /// On the canvas: Delete and Backspace take the selected element away while
  /// editing, Escape lets go of it, ⌘Z or Ctrl+Z takes a change back (with Shift, does
  /// it again). Anything else goes on to the screen — and while a snippet is written,
  /// everything but Escape stays with its field.
  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return .ignored;
    final key = event.logicalKey;
    if (key == .escape && _writing != null) {
      _keys.requestFocus();
      return .handled;
    }
    // Typed into a field on the canvas — a snippet written in place — the keys are
    // the field's. In the browser the field leaves Backspace, Delete and ⌘Z to the
    // browser, so they came on to here: Backspace took the snippet being written
    // away instead of its last letter.
    if (!_keys.hasPrimaryFocus) return .ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    if (_editable && command && key == .keyZ) {
      unawaited(keys.isShiftPressed ? _viewModel.redo() : _viewModel.undo());
      return .handled;
    }
    if (key == .escape && _tool != .select) {
      _takeUp(.select);
      return .handled;
    }
    if (key == .escape && _deciding != null) {
      setState(() => _deciding = null);
      return .handled;
    }
    if (_selection == null && _group.isEmpty) return .ignored;
    if (_editable && (key == .delete || key == .backspace)) {
      _deleteSelection();
      return .handled;
    }
    if (key == .escape) {
      _select(null);
      return .handled;
    }
    return .ignored;
  }

  // --- Opening, editing ---------------------------------------------------------

  Future<void> _open(MindmapNode node) async {
    final state = _state;
    if (state == null) return;
    if (state.conflicts[node.id] != null && !_editable) {
      _decideOnMap(node.id);
      return;
    }
    if (_editable) {
      await _editContent(node);
      return;
    }
    // Read, a link element leads to its target; a picture opens large.
    if (node.target case final target? when node.kind == MindmapKinds.link) {
      final item = state.targetOf(target);
      if (item != null) {
        await openLinkTarget(context, ref, item, leave: _back);
      }
      return;
    }
    if (node.imageId case final id? when node.kind == MindmapKinds.image) {
      await showImageGallery(
        context,
        imageIds: [id],
        initial: 0,
        heroTag: (_) => MindmapElementView.pictureTagOf(node.id),
        aspects: {id: node.width / node.height},
        previewWidth: (node.width * MediaQuery.devicePixelRatioOf(context))
            .round(),
        onShown: (_) {},
      );
    }
  }

  Future<void> _editContent(MindmapNode node) async {
    switch (node.kind) {
      case MindmapKinds.plain:
        // Written where it stands, not in a sheet over the map.
        _write(node);
      case MindmapKinds.note:
        final text = await showMindmapNoteSheet(
          context,
          pageId: widget.pageId,
          text: node.text,
        );
        if (text != null) await _viewModel.setText(node, text);
      case MindmapKinds.image:
        // Another picture: as wide as the one before, in its own shape.
        final picture = await _pickPicture();
        if (picture == null) return;
        await _viewModel.setText(
          node,
          picture.markdown,
          box: (
            width: node.width,
            height: math.max(1, (node.width / picture.aspect).round()),
          ),
        );
      case MindmapKinds.link:
        final markdown = await showLinkPicker(context);
        final target = markdown == null ? null : linkAddressOf(markdown);
        if (target != null) await _viewModel.setTarget(node, target);
      case MindmapKinds.member:
        final member = await _pickMember(current: memberIdOf(node.target));
        if (member != null) {
          await _viewModel.setTarget(node, memberAddressOf(member.id));
        }
    }
  }

  /// Someone of the family, for a member element.
  Future<Member?> _pickMember({String? current}) {
    final members = [...?_state?.members.values]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return showMindmapMemberSheet(context, members: members, current: current);
  }

  /// A new element of [kind] — its content asked for first: a cancelled sheet or
  /// picker places nothing. [at] is where it was dropped; `null`: the middle of the
  /// view.
  Future<void> _place(String kind, Offset? at) async {
    final l = L.of(context);
    // As large as the one of its kind placed or resized last here — a row of
    // pictures or notes comes out alike.
    final last = switch (_state?.lastSizes[kind]) {
      (:final width, :final height) => Size(
        width.toDouble(),
        height.toDouble(),
      ),
      null => null,
    };
    String text = '';
    String? target;
    String? linkView;
    Size size;
    switch (kind) {
      case MindmapKinds.plain:
        // Written on the canvas where it lands; on the map once it holds a word.
        final box = _writingBox(l.mindmapPlainHint, null, isNew: true);
        final half = Offset(box.width / 2, box.height / 2);
        final corner = at == null
            ? _middle(Size(box.width.toDouble(), box.height.toDouble()))
            : (x: (at.dx - half.dx).round(), y: (at.dy - half.dy).round());
        _write(
          MindmapNode(
            id: _draftId,
            ownerId: '',
            version: 0,
            pageId: widget.pageId,
            kind: MindmapKinds.plain,
            x: corner.x,
            y: corner.y,
            width: box.width,
            height: box.height,
            layer: (_state?.map ?? .empty).topLayer,
            text: '',
          ),
          isNew: true,
        );
        return;
      case MindmapKinds.note:
        final typed = await showMindmapNoteSheet(
          context,
          pageId: widget.pageId,
          text: '',
        );
        if (typed == null || typed.trim().isEmpty) return;
        text = typed;
        size = last ?? HiwiskiMetrics.mindmapNoteSize;
      case MindmapKinds.image:
        final picture = await _pickPicture();
        if (picture == null) return;
        text = picture.markdown;
        // In the picture's own shape, within the room a new one takes.
        // Taken after the last picture, it is as high, in its own shape.
        const room = HiwiskiMetrics.mindmapImageSize;
        size = switch (last) {
          final last? => Size(last.height * picture.aspect, last.height),
          null when picture.aspect >= room.width / room.height => Size(
            room.width,
            room.width / picture.aspect,
          ),
          null => Size(room.height * picture.aspect, room.height),
        };
      case MindmapKinds.link:
        final markdown = await showLinkPicker(context);
        target = markdown == null ? null : linkAddressOf(markdown);
        if (target == null) return;
        // Shown with what it points to: the title alone said too little. A link
        // last placed as its title only is no measure for one showing content.
        linkView = MindmapLinkViews.content;
        size = switch (last) {
          final last?
              when last.height > HiwiskiMetrics.mindmapLinkSize.height =>
            last,
          _ => HiwiskiMetrics.mindmapLinkContentSize,
        };
      case MindmapKinds.member:
        final member = await _pickMember();
        if (member == null) return;
        target = memberAddressOf(member.id);
        size = last ?? HiwiskiMetrics.mindmapMemberSize;
      default:
        return;
    }
    if (!mounted) return;
    final corner = at == null
        ? _middle(size)
        : (
            x: (at.dx - size.width / 2).round(),
            y: (at.dy - size.height / 2).round(),
          );
    final id = await addMindmapNodeMutation.run(
      ref,
      (tsx) => tsx
          .get(mindmapViewModelProvider(widget.pageId).notifier)
          .addNode(
            kind: kind,
            at: corner,
            // A very wide picture is still a line high.
            size: (
              width: math.max(1, size.width.round()),
              height: math.max(1, size.height.round()),
            ),
            text: text,
            target: target,
            linkView: linkView,
          ),
    );
    if (mounted) _select(.node(id));
  }

  /// One picture, picked and kept for the page, as the Markdown a picture element
  /// holds, and its shape — `null` when none was picked.
  Future<({String markdown, double aspect})?> _pickPicture() async {
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = (await pickImageFiles(single: true)).firstOrNull;
      if (file == null || !mounted) return null;
      final aspect = await _aspectOf(file.bytes);
      if (!mounted) return null;
      final markdown = await keepMindmapImagesMutation.run(
        ref,
        (tsx) => tsx
            .get(mindmapViewModelProvider(widget.pageId).notifier)
            .keepImages([file]),
      );
      return (markdown: markdown, aspect: aspect);
    } on Object catch (error) {
      // Not the server's answer: a picture that could not be read.
      debugPrint('hiwiski: mind map picture not added: $error');
      messenger.showSnackBar(SnackBar(content: Text(l.wikiImagesFailed)));
      return null;
    }
  }

  /// A picture's width over its height, as it is shown — turned as its camera said.
  /// Decoded small: only the shape is wanted, not a phone's photo in memory.
  static Future<double> _aspectOf(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _probeWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final aspect = image.width / math.max(1, image.height);
      image.dispose();
      return aspect;
    } finally {
      codec.dispose();
    }
  }

  static const _probeWidth = 256;

  /// The size of a snippet of [text] at text [size], wrapped at [wrap]: just as large
  /// as its text.
  ({int width, int height}) _plainBox(
    String text,
    String? size, {
    required double wrap,
  }) {
    final box = MindmapElementView.plainBoxOf(
      context,
      text,
      size,
      maxWidth: wrap,
    );
    return (
      width: math.max(1, box.width.round()),
      height: math.max(1, box.height.round()),
    );
  }

  /// The size of a snippet while it is written: as the field lays out [text] — the
  /// hint while it is empty — wrapped where the snippet wraps.
  ({int width, int height}) _writingBox(
    String text,
    String? size, {
    required bool isNew,
    int? width,
  }) {
    final box = MindmapElementView.plainBoxOf(
      context,
      text,
      size,
      maxWidth: isNew || width == null
          ? HiwiskiMetrics.mindmapPlainWrap
          : math.max(width.toDouble(), HiwiskiMetrics.mindmapPlainWrap),
      writing: true,
    );
    return (
      width: math.max(1, box.width.round()),
      height: math.max(1, box.height.round()),
    );
  }

  /// Starts writing [node] on the canvas — [isNew]: one not on the map yet.
  void _write(MindmapNode node, {bool isNew = false}) {
    _typed
      ..text = node.text
      ..selection = TextSelection.collapsed(offset: node.text.length);
    setState(() {
      _writing = (node: node, isNew: isNew);
      _selection = isNew ? null : .node(node.id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _typing.requestFocus();
      _camera.show(node.bounds);
    });
  }

  /// Keeps what was written: a new snippet goes on the map, one there takes its new
  /// text and size. Emptied, a new one is dropped and one there is taken away.
  Future<void> _finishWriting() async {
    final writing = _writing;
    if (writing == null) return;
    final node = writing.node;
    // A line break left at the end would be an empty line under the text.
    final text = _typed.text.trimRight();
    final box = _plainBox(
      text,
      node.textSize,
      wrap: writing.isNew
          ? HiwiskiMetrics.mindmapPlainWrap
          : math.max(node.width.toDouble(), HiwiskiMetrics.mindmapPlainWrap),
    );
    final written = node.changed(
      text: text,
      width: box.width,
      height: box.height,
    );
    final empty = text.trim().isEmpty;
    setState(() {
      _writing = null;
      // Let go of at once, the old text — or nothing — stood there for a moment.
      _held = empty || text == node.text ? null : written;
      _heldFrom = writing.isNew ? null : node;
      _heldAs = null;
    });
    if (empty) {
      if (!writing.isNew) await _viewModel.delete(node);
      return;
    }
    if (writing.isNew) {
      final id = await addMindmapNodeMutation.run(
        ref,
        (tsx) => tsx
            .get(mindmapViewModelProvider(widget.pageId).notifier)
            .addNode(
              kind: MindmapKinds.plain,
              at: (x: node.x, y: node.y),
              size: box,
              text: text,
            ),
      );
      if (mounted) _placedWritten(id);
    } else if (text != node.text) {
      await _viewModel.setText(node, text, box: box);
    }
  }

  /// A new snippet is on the map as [id]: held until the map has it, and selected.
  void _placedWritten(String id) {
    setState(() => _heldAs = id);
    _arrived(_state?.map);
    _select(.node(id));
  }

  /// What is held until the map has it — strokes just drawn, a snippet just written
  /// — let go of the moment it has: held on, it stood there again once "Undo" took
  /// it back, and "Undo" seemed to skip it.
  void _arrived(Mindmap? map) {
    if (map == null) return;
    final strokes = [
      for (final stroke in _strokes)
        if (map.nodes.any((node) => node.points == stroke.points)) stroke,
    ];
    final held = _held;
    // A new snippet has arrived once it is there; a rewritten one once it is no
    // longer as it was.
    final heldAs = _heldAs;
    final written =
        held != null &&
        (_heldFrom == null
            ? heldAs != null && map.node(heldAs) != null
            : map.node(held.id) != _heldFrom);
    if (strokes.isEmpty && !written) return;
    setState(() {
      _strokes.removeWhere(strokes.contains);
      if (written) {
        _held = null;
        _heldFrom = null;
        _heldAs = null;
      }
    });
  }

  /// The id a snippet has while it is written and not on the map yet.
  static const _draftId = 'mindmap-draft';

  /// Shows the conflict of [id] on the map: this device's version beside the map's,
  /// the bar below to decide it — no sheet over what is to be compared.
  void _decideOnMap(String id) {
    final state = _state;
    if (state == null || !state.conflicts.containsKey(id)) return;
    setState(() {
      _deciding = id;
      _marked = id;
      _selection = null;
    });
    final node = state.map.node(id);
    final conflicts = state.conflicts[id];
    final bounds = node != null && conflicts != null
        ? node.bounds.expandToInclude(
            mineBoundsOf(
              node,
              mineOf(node, conflicts),
              HiwiskiMetrics.mindmapConflictGap,
            ),
          )
        : _boundsOf(state, id);
    // After the frame: the bar is in place, and the camera keeps clear of it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && bounds != null) _camera.show(bounds);
    });
  }

  /// From the banner over the map: an element of this map is decided here.
  bool _fromBanner(String pageId, String id) {
    if (pageId != widget.pageId) return false;
    _decideOnMap(id);
    return true;
  }

  Future<void> _decided(
    List<SyncConflict> conflicts, {
    required bool mine,
  }) async {
    setState(() => _deciding = null);
    await (mine
        ? _viewModel.takeMine(conflicts)
        : _viewModel.keepTheirs(conflicts));
  }

  void _showConflicts() {
    final id = _state?.conflicts.keys.firstOrNull;
    if (id != null) _decideOnMap(id);
  }

  // --- The corner: its menus, and the selection's choices -------------------------

  /// The menus in the corner while editing: what is added, how it is drawn, what a
  /// finger does.
  List<MindmapCornerMenu> _menus(MindmapState state) {
    final l = L.of(context);
    final drawn = state.map.nodes.any(
      (node) => node.kind == MindmapKinds.drawing,
    );
    return [
      MindmapCornerMenu(
        key: MindmapKeys.addMenu,
        icon: HiwiskiSymbols.add,
        label: l.mindmapMenuAdd,
        on: _tool == .connect,
        options: [
          for (final (kind, icon, label) in [
            (MindmapKinds.plain, HiwiskiSymbols.title, l.mindmapToolPlain),
            (MindmapKinds.note, HiwiskiSymbols.stickyNote2, l.mindmapToolNote),
            (MindmapKinds.image, HiwiskiSymbols.image, l.mindmapToolImage),
            (MindmapKinds.link, HiwiskiSymbols.link, l.mindmapToolLink),
            (MindmapKinds.member, HiwiskiSymbols.person, l.mindmapToolMember),
          ])
            MindmapCornerOption(
              key: MindmapKeys.tool(kind),
              icon: icon,
              label: label,
              dragged: kind,
              onTap: () => unawaited(_place(kind, null)),
            ),
          // A connection: its kinds a level below, each drawn from one element
          // to the next, and on from there.
          MindmapCornerOption(
            key: MindmapKeys.edgeTool,
            icon: HiwiskiSymbols.polyline,
            label: l.mindmapToolEdge,
            on: _tool == .connect,
            onTap: () => setState(() => _submenu = .edges),
          ),
        ],
      ),
      MindmapCornerMenu(
        key: MindmapKeys.drawMenu,
        icon: HiwiskiSymbols.draw,
        label: l.mindmapMenuDraw,
        on: _tool == .pen || _tool == .eraser || _tool == .shape,
        options: [
          MindmapCornerOption(
            key: MindmapKeys.pen,
            icon: HiwiskiSymbols.draw,
            label: l.mindmapToolPen,
            on: _tool == .pen,
            onTap: () => _takeUp(_tool == .pen ? .select : .pen),
          ),
          // Shapes a level below, drawn in the colour and thickness chosen here.
          MindmapCornerOption(
            key: MindmapKeys.shapes,
            icon: HiwiskiSymbols.category,
            label: l.mindmapToolShapes,
            on: _tool == .shape,
            onTap: () => setState(() => _submenu = .shapes),
          ),
          MindmapCornerOption(
            key: MindmapKeys.eraser,
            icon: HiwiskiSymbols.inkEraser,
            label: l.mindmapToolEraser,
            on: _tool == .eraser,
            onTap: () => _takeUp(_tool == .eraser ? .select : .eraser),
          ),
          MindmapCornerOption(
            key: MindmapKeys.penColor,
            icon: HiwiskiSymbols.palette,
            label: l.mindmapPenColor,
            swatch: _penInk(context),
            onTap: () => unawaited(_choosePenColor()),
          ),
          MindmapCornerOption(
            key: MindmapKeys.strokeWidth,
            icon: HiwiskiSymbols.lineWeight,
            label: l.mindmapStrokeWidth,
            onTap: () => unawaited(_choosePenWidth()),
          ),
        ],
      ),
      MindmapCornerMenu(
        key: MindmapKeys.toolsMenu,
        icon: HiwiskiSymbols.arrowSelectorTool,
        label: l.mindmapMenuTools,
        on: _tool == .lasso || _tool == .rectangle,
        options: [
          for (final (tool, key, icon, label) in [
            (
              MindmapTool.select,
              MindmapKeys.select,
              HiwiskiSymbols.arrowSelectorTool,
              l.mindmapToolSelect,
            ),
            (
              MindmapTool.lasso,
              MindmapKeys.lasso,
              HiwiskiSymbols.lassoSelect,
              l.mindmapToolLasso,
            ),
            (
              MindmapTool.rectangle,
              MindmapKeys.rectangle,
              HiwiskiSymbols.highlightAlt,
              l.mindmapToolRectangle,
            ),
          ])
            MindmapCornerOption(
              key: key,
              icon: icon,
              label: label,
              on: _tool == tool,
              onTap: () => _takeUp(tool),
            ),
          MindmapCornerOption(
            key: MindmapKeys.fit,
            icon: HiwiskiSymbols.fitScreen,
            label: l.mindmapFit,
            onTap: () => _camera.fit(state.map.bounds, glide: true),
          ),
          MindmapCornerOption(
            key: MindmapKeys.snap,
            icon: HiwiskiSymbols.straighten,
            label: l.mindmapSnap,
            on: state.snap,
            onTap: () => _viewModel.setSnap(!state.snap),
          ),
          MindmapCornerOption(
            key: MindmapKeys.grid,
            icon: HiwiskiSymbols.grid4x4,
            label: l.mindmapGrid,
            on: state.grid,
            onTap: () => _viewModel.setGrid(!state.grid),
          ),
          // Only where there is something drawn to hide.
          if (drawn)
            MindmapCornerOption(
              key: MindmapKeys.drawings,
              icon: _drawingsHidden
                  ? HiwiskiSymbols.visibilityOff
                  : HiwiskiSymbols.visibility,
              label: _drawingsHidden
                  ? l.mindmapDrawingsShow
                  : l.mindmapDrawingsHide,
              on: _drawingsHidden,
              onTap: _toggleDrawings,
            ),
          if (state.map.nodes.isNotEmpty)
            MindmapCornerOption(
              key: MindmapKeys.picture,
              icon: HiwiskiSymbols.download,
              label: l.mindmapPicture,
              onTap: () => unawaited(_savePicture()),
            ),
        ],
      ),
    ];
  }

  /// What can be done with the selected element or connection.
  List<MindmapCornerOption> _selectionOptions(
    MindmapState state,
    MindmapSelection selection,
  ) {
    final l = L.of(context);
    final node = selection.edge ? null : state.map.node(selection.id);
    final edge = selection.edge ? state.map.edge(selection.id) : null;
    final kind = node?.kind;
    final viewModel = _viewModel;
    final drawing = kind == MindmapKinds.drawing;
    // A picture is its picture, a member their circle, a stroke its line: no text.
    final texted =
        node != null &&
        kind != MindmapKinds.image &&
        kind != MindmapKinds.member &&
        !drawing;
    return [
      if (state.conflicts.containsKey(selection.id))
        MindmapCornerOption(
          key: MindmapKeys.conflicts,
          icon: HiwiskiSymbols.merge,
          label: l.mindmapConflictElement,
          onTap: () => _decideOnMap(selection.id),
        ),
      // A stroke is drawn again, not edited.
      if (!drawing)
        MindmapCornerOption(
          key: MindmapKeys.editContent,
          icon: HiwiskiSymbols.edit,
          label: edge != null ? l.mindmapEdgeText : l.mindmapEditContent,
          onTap: () async {
            if (node != null) {
              await _editContent(node);
            } else if (edge != null) {
              final text = await showMindmapTextSheet(
                context,
                title: L.of(context).mindmapEdgeText,
                text: edge.text,
              );
              if (text != null) await viewModel.setEdgeText(edge, text);
            }
          },
        ),
      // A snippet of text has no surface to colour, only its text.
      if (kind != MindmapKinds.image && kind != MindmapKinds.plain)
        MindmapCornerOption(
          key: MindmapKeys.color,
          icon: HiwiskiSymbols.palette,
          label: l.mindmapColor,
          onTap: () async {
            final chosen = await showMindmapColorSheet(
              context,
              current: node?.color ?? edge?.color,
              recent: state.ownColors,
            );
            if (chosen == null) return;
            if (node != null) await viewModel.setColor(node, chosen.color);
            if (edge != null) await viewModel.setEdgeColor(edge, chosen.color);
          },
        ),
      // Early on the arc: in reach without turning it.
      MindmapCornerOption(
        key: MindmapKeys.delete,
        icon: HiwiskiSymbols.deleteOutline,
        label: edge != null ? l.mindmapDeleteEdge : l.mindmapDeleteElement,
        onTap: _deleteSelection,
      ),
      if (edge != null)
        MindmapCornerOption(
          key: MindmapKeys.edgeStyle,
          icon: HiwiskiSymbols.polyline,
          label: l.mindmapEdgeStyle,
          glyph: (canvas, size, color) => paintEdgeGlyph(canvas, size, color, (
            line: edge.line,
            arrows: edge.arrows,
          )),
          onTap: () async {
            final style = await showMindmapChoiceSheet<MindmapEdgeStyle>(
              context,
              title: l.mindmapEdgeStyle,
              current: (line: edge.line, arrows: edge.arrows),
              choices: [
                for (final style in mindmapEdgeStyles)
                  (style, _edgeStyleLabel(l, style)),
              ],
            );
            if (style != null) {
              await viewModel.setEdgeStyle(
                edge,
                line: style.line,
                arrows: style.arrows,
              );
            }
          },
        ),
      if (edge != null)
        MindmapCornerOption(
          key: MindmapKeys.strokeWidth,
          icon: HiwiskiSymbols.lineWeight,
          label: l.mindmapLineWidth,
          onTap: () async {
            final width = await _chooseWidth(
              title: l.mindmapLineWidth,
              current: edge.strokeWidth,
              withOwn: true,
            );
            if (width != null) await viewModel.setEdgeWidth(edge, width.value);
          },
        ),
      if (node != null && drawing)
        MindmapCornerOption(
          key: MindmapKeys.strokeWidth,
          icon: HiwiskiSymbols.lineWeight,
          label: l.mindmapStrokeWidth,
          onTap: () async {
            final width = (await _chooseWidth(
              title: l.mindmapStrokeWidth,
              current: node.strokeWidth,
              withOwn: false,
            ))?.value;
            if (width != null) await viewModel.setStrokeWidth(node, width);
          },
        ),
      if (texted)
        MindmapCornerOption(
          key: MindmapKeys.textColor,
          icon: HiwiskiSymbols.formatColorText,
          label: l.mindmapTextColor,
          onTap: () async {
            final chosen = await showMindmapColorSheet(
              context,
              current: node.textColor,
              recent: state.ownColors,
              text: (surface: node.hasSurface, fill: node.color),
            );
            if (chosen != null) {
              await viewModel.setTextColor(node, chosen.color);
            }
          },
        ),
      if (texted)
        MindmapCornerOption(
          key: MindmapKeys.textSize,
          icon: HiwiskiSymbols.formatSize,
          label: l.mindmapTextSize,
          onTap: () => unawaited(_chooseTextSize(node)),
        ),
      // Only what has a surface has an outline.
      if (kind == MindmapKinds.note || kind == MindmapKinds.link)
        MindmapCornerOption(
          key: MindmapKeys.shape,
          icon: HiwiskiSymbols.category,
          label: l.mindmapShape,
          onTap: () async {
            final shape = await showMindmapChoiceSheet<String>(
              context,
              title: l.mindmapShape,
              current: node?.shape ?? MindmapShapes.rounded,
              choices: [
                (MindmapShapes.rounded, l.mindmapShapeRounded),
                (MindmapShapes.rectangle, l.mindmapShapeRectangle),
                (MindmapShapes.pill, l.mindmapShapePill),
                (MindmapShapes.ellipse, l.mindmapShapeEllipse),
                (MindmapShapes.diamond, l.mindmapShapeDiamond),
              ],
            );
            if (shape != null && node != null) {
              await viewModel.setShape(node, shape);
            }
          },
        ),
      if (kind == MindmapKinds.link)
        MindmapCornerOption(
          key: MindmapKeys.linkView,
          icon: HiwiskiSymbols.visibility,
          label: l.mindmapLinkView,
          onTap: () async {
            final view = await showMindmapChoiceSheet<String>(
              context,
              title: l.mindmapLinkView,
              current: node?.linkView ?? MindmapLinkViews.title,
              choices: [
                (MindmapLinkViews.title, l.mindmapLinkTitle),
                (MindmapLinkViews.content, l.mindmapLinkContent),
              ],
            );
            const room = HiwiskiMetrics.mindmapLinkContentSize;
            if (view != null && node != null) {
              await viewModel.setLinkView(
                node,
                view,
                room: (width: room.width.round(), height: room.height.round()),
              );
            }
          },
        ),
      if (node != null) ...[
        MindmapCornerOption(
          key: MindmapKeys.layerUp,
          icon: HiwiskiSymbols.flipToFront,
          label: l.mindmapLayerUp,
          onTap: () => unawaited(viewModel.raise(node)),
        ),
        MindmapCornerOption(
          key: MindmapKeys.layerDown,
          icon: HiwiskiSymbols.flipToBack,
          label: l.mindmapLayerDown,
          onTap: () => unawaited(viewModel.lower(node)),
        ),
        MindmapCornerOption(
          key: MindmapKeys.layerFront,
          icon: HiwiskiSymbols.flipToFront,
          label: l.mindmapLayerFront,
          onTap: () => unawaited(viewModel.toFront(node)),
        ),
        MindmapCornerOption(
          key: MindmapKeys.layerBack,
          icon: HiwiskiSymbols.flipToBack,
          label: l.mindmapLayerBack,
          onTap: () => unawaited(viewModel.toBack(node)),
        ),
        // A stroke is part of the picture, not a thought to connect.
        if (!drawing)
          MindmapCornerOption(
            key: MindmapKeys.connect,
            icon: HiwiskiSymbols.hub,
            label: l.mindmapConnect,
            onTap: () async {
              final other = await showMindmapConnectSheet(
                context,
                map: state.map,
                from: node,
                linkTarget: state.targetOf,
              );
              if (other != null) await viewModel.connect(node, other);
            },
          ),
      ],
    ];
  }

  /// What can be done with a group: given one colour, or taken away — each as one
  /// step.
  List<MindmapCornerOption> _groupOptions(
    MindmapState state,
    List<MindmapNode> group,
  ) {
    final l = L.of(context);
    return [
      MindmapCornerOption(
        key: MindmapKeys.color,
        icon: HiwiskiSymbols.palette,
        label: l.mindmapColor,
        onTap: () async {
          final chosen = await showMindmapColorSheet(
            context,
            current: null,
            recent: state.ownColors,
          );
          if (chosen != null) {
            await _viewModel.setColors(group, chosen.color);
          }
        },
      ),
      // Lined up, spread out, made one size — a level below.
      MindmapCornerOption(
        key: MindmapKeys.align,
        icon: HiwiskiSymbols.alignHorizontalLeft,
        label: l.mindmapAlign,
        onTap: () => setState(() => _submenu = .align),
      ),
      MindmapCornerOption(
        key: MindmapKeys.delete,
        icon: HiwiskiSymbols.deleteOutline,
        label: l.mindmapDeleteGroup,
        onTap: _deleteSelection,
      ),
    ];
  }

  /// What a group can be lined up by: aligned, spread out, made one size — each one
  /// step.
  List<MindmapCornerOption> _alignOptions(L l, List<MindmapNode> group) => [
    for (final (align, icon, label) in [
      (
        MindmapAlign.left,
        HiwiskiSymbols.alignHorizontalLeft,
        l.mindmapAlignLeft,
      ),
      (
        MindmapAlign.centre,
        HiwiskiSymbols.alignHorizontalCenter,
        l.mindmapAlignCentre,
      ),
      (
        MindmapAlign.right,
        HiwiskiSymbols.alignHorizontalRight,
        l.mindmapAlignRight,
      ),
      (MindmapAlign.top, HiwiskiSymbols.alignVerticalTop, l.mindmapAlignTop),
      (
        MindmapAlign.middle,
        HiwiskiSymbols.alignVerticalCenter,
        l.mindmapAlignMiddle,
      ),
      (
        MindmapAlign.bottom,
        HiwiskiSymbols.alignVerticalBottom,
        l.mindmapAlignBottom,
      ),
    ])
      MindmapCornerOption(
        key: MindmapKeys.arrange(align.name),
        icon: icon,
        label: label,
        onTap: () => _moveGroup(group, (boxes) => alignBoxes(boxes, align)),
      ),
    // Spreading out takes a first, a last and one between.
    if (group.length >= _spreadAtLeast) ...[
      MindmapCornerOption(
        key: MindmapKeys.arrange(_spreadAcross),
        icon: HiwiskiSymbols.horizontalDistribute,
        label: l.mindmapDistributeAcross,
        onTap: () => _moveGroup(
          group,
          (boxes) => distributeBoxes(boxes, horizontal: true),
        ),
      ),
      MindmapCornerOption(
        key: MindmapKeys.arrange(_spreadDown),
        icon: HiwiskiSymbols.verticalDistribute,
        label: l.mindmapDistributeDown,
        onTap: () => _moveGroup(
          group,
          (boxes) => distributeBoxes(boxes, horizontal: false),
        ),
      ),
    ],
    for (final (name, icon, label, width, height) in [
      (_sameWidth, HiwiskiSymbols.width, l.mindmapSameWidth, true, false),
      (_sameHeight, HiwiskiSymbols.height, l.mindmapSameHeight, false, true),
      (_sameSize, HiwiskiSymbols.aspectRatio, l.mindmapSameSize, true, true),
    ])
      MindmapCornerOption(
        key: MindmapKeys.arrange(name),
        icon: icon,
        label: label,
        onTap: () => _sizeGroup(group, width: width, height: height),
      ),
  ];

  /// Moves [group] to where [arrange] puts the boxes they cover as turned.
  void _moveGroup(
    List<MindmapNode> group,
    Map<String, Rect> Function(Map<String, Rect> boxes) arrange,
  ) {
    final placed = arrange({
      for (final node in group) node.id: node.turnedBounds,
    });
    unawaited(
      _viewModel.arrange({
        for (final node in group)
          if (placed[node.id] case final box?)
            node: node.moved(
              Offset(
                (box.left - node.turnedBounds.left).roundToDouble(),
                (box.top - node.turnedBounds.top).roundToDouble(),
              ),
            ),
      }),
    );
  }

  /// Gives [group] the width and/or height of its largest — a picture and a
  /// member's circle keeping their shape, a snippet as high as its text then needs.
  void _sizeGroup(
    List<MindmapNode> group, {
    required bool width,
    required bool height,
  }) {
    final sized = sameSizeBoxes(
      {for (final node in group) node.id: node.bounds},
      width: width,
      height: height,
      aspects: {
        for (final node in group)
          if (node.keepsShape) node.id: node.width / node.height,
      },
    );
    unawaited(
      _viewModel.arrange({
        for (final node in group)
          if (sized[node.id] case final box?)
            node: switch (node.kind) {
              MindmapKinds.plain => () {
                final fitted = _plainBox(
                  node.text,
                  node.textSize,
                  wrap: box.width,
                );
                return node.resizedTo(fitted.width, fitted.height);
              }(),
              _ => node.resizedTo(
                math.max(1, box.width.round()),
                math.max(1, box.height.round()),
              ),
            },
      }),
    );
  }

  /// A thickness: one of a few, or — [withOwn] — none of the element's own
  /// (`value` `null`). `null`: nothing was chosen.
  Future<({int? value})?> _chooseWidth({
    required String title,
    required int? current,
    required bool withOwn,
  }) async {
    final l = L.of(context);
    final chosen = await showMindmapChoiceSheet<int>(
      context,
      title: title,
      current: current ?? (withOwn ? 0 : null),
      choices: [
        if (withOwn) (0, l.mindmapColorNone),
        for (final width in HiwiskiMetrics.mindmapLineWidths) (width, '$width'),
      ],
      own: (
        min: 1,
        max: mindmapMaxStrokeWidth,
        value: current,
        toValue: (number) => number,
      ),
    );
    if (chosen == null) return null;
    // "Default": the app's own — a line has one, a stroke does not.
    return (value: chosen == 0 ? null : chosen);
  }

  Future<void> _chooseTextSize(MindmapNode node) async {
    final l = L.of(context);
    final size = await showMindmapChoiceSheet<String>(
      context,
      title: l.mindmapTextSize,
      current: node.textSize ?? MindmapTextSizes.medium,
      choices: [
        (MindmapTextSizes.small, l.mindmapTextSmall),
        (MindmapTextSizes.medium, l.mindmapTextMedium),
        (MindmapTextSizes.large, l.mindmapTextLarge),
        (MindmapTextSizes.xLarge, l.mindmapTextXLarge),
      ],
      own: (
        min: mindmapMinTextPixels,
        max: mindmapMaxTextPixels,
        value: mindmapTextPixels(node.textSize),
        toValue: (number) => '$number',
      ),
    );
    if (size == null || !mounted) return;
    await _viewModel.setTextSize(
      node,
      size,
      // A snippet is as large as its text, at any size of it.
      box: node.kind == MindmapKinds.plain
          ? _plainBox(
              node.text,
              size,
              wrap: math.max(
                node.width.toDouble(),
                HiwiskiMetrics.mindmapPlainWrap,
              ),
            )
          : null,
    );
  }

  Future<void> _choosePenWidth() async {
    final l = L.of(context);
    final width = await showMindmapChoiceSheet<double>(
      context,
      title: l.mindmapStrokeWidth,
      current: _penWidth,
      choices: [
        for (final width in HiwiskiMetrics.mindmapPenWidths)
          (width, '${width.round()}'),
      ],
      own: (
        min: 1,
        max: HiwiskiMetrics.mindmapPenMaxWidth.round(),
        value: _penWidth.round(),
        toValue: (number) => number.toDouble(),
      ),
    );
    if (width != null && mounted) setState(() => _penWidth = width);
  }

  void _toggleDrawings() => setState(() {
    _drawingsHidden = !_drawingsHidden;
    _selection = null;
    _group = const {};
    if (_drawingsHidden) _tool = .select;
  });

  void _deleteSelection() {
    final state = _state;
    final selection = _selection;
    if (state == null || !_editable) return;
    if (_group.isNotEmpty) {
      unawaited(
        _viewModel.deleteAll([for (final id in _group) ?state.map.node(id)]),
      );
      _select(null);
      return;
    }
    if (selection == null) return;
    if (selection.edge) {
      if (state.map.edge(selection.id) case final edge?) {
        unawaited(_viewModel.deleteEdge(edge));
      }
    } else if (state.map.node(selection.id) case final node?) {
      unawaited(_viewModel.delete(node));
    }
    _select(null);
  }

  void _toggleEditing() {
    setState(() {
      _editing = !_editing;
      _selection = null;
      _group = const {};
      _menu = null;
      _submenu = null;
      _tool = .select;
    });
    _keys.requestFocus();
  }

  /// The pen or the eraser taken up, or put down.
  void _takeUp(MindmapTool tool) {
    setState(() {
      _tool = tool;
      if (tool != .select) {
        _selection = null;
        _group = const {};
      }
      // What is drawn and erased is seen.
      if (tool case .pen || .eraser || .shape) _drawingsHidden = false;
    });
    _keys.requestFocus();
  }

  /// A menu in the corner opened, or closed: the tool it holds is put down with it
  /// — back from the pen, the finger selects again.
  void _openMenu(int? menu) {
    final holder = switch (_tool) {
      .connect => _addMenu,
      .pen || .eraser || .shape => _drawMenu,
      .lasso || .rectangle => _toolsMenu,
      .select => null,
    };
    setState(() {
      _menu = menu;
      _submenu = null;
      if (holder != null && holder != menu) _tool = .select;
    });
    _keys.requestFocus();
  }

  /// The button in the middle: a level up — from the kinds of connections or the
  /// shapes, putting their tool down — or the menu closed.
  void _cornerBack() {
    if (_submenu == .align) return setState(() => _submenu = null);
    if (_submenu == null) return _openMenu(null);
    setState(() {
      _submenu = null;
      if (_tool case .connect || .shape) _tool = .select;
    });
    _keys.requestFocus();
  }

  /// The level below a choice that is open, with its own choices — of a menu, or
  /// of what is selected.
  MindmapCornerSubmenu? _submenuOf(L l, MindmapState state) =>
      switch (_submenu) {
        null => null,
        // Only while a group is selected, the menus' levels only while none is.
        .align when _group.length > 1 => (
          id: _Submenu.align,
          options: _alignOptions(l, [
            for (final id in _group) ?state.map.node(id),
          ]),
        ),
        .align => null,
        _ when _selection != null || _group.isNotEmpty => null,
        .edges => (
          id: _Submenu.edges,
          options: [
            for (final (index, style) in mindmapEdgeStyles.indexed)
              MindmapCornerOption(
                key: MindmapKeys.edgeStyleOf(index),
                icon: HiwiskiSymbols.polyline,
                label: _edgeStyleLabel(l, style),
                glyph: (canvas, size, color) =>
                    paintEdgeGlyph(canvas, size, color, style),
                on: _tool == .connect && _edgeStyle == style,
                onTap: () {
                  final again = _tool == .connect && _edgeStyle == style;
                  setState(() => _edgeStyle = style);
                  _takeUp(again ? .select : .connect);
                },
              ),
            // What every connection drawn from now on is drawn with.
            MindmapCornerOption(
              key: MindmapKeys.edgeColor,
              icon: HiwiskiSymbols.palette,
              label: l.mindmapColor,
              swatch: _edgeInk(context),
              onTap: () => unawaited(_chooseEdgeColor()),
            ),
            MindmapCornerOption(
              key: MindmapKeys.edgeWidth,
              icon: HiwiskiSymbols.lineWeight,
              label: l.mindmapLineWidth,
              onTap: () async {
                final width = await _chooseWidth(
                  title: l.mindmapLineWidth,
                  current: _edgeWidth,
                  withOwn: true,
                );
                if (width != null && mounted) {
                  setState(() => _edgeWidth = width.value);
                }
              },
            ),
          ],
        ),
        .shapes => (
          id: _Submenu.shapes,
          options: [
            for (final shape in MindmapPenShape.values)
              MindmapCornerOption(
                key: MindmapKeys.penShape(shape.name),
                icon: HiwiskiSymbols.category,
                label: _penShapeLabel(l, shape),
                glyph: (canvas, size, color) =>
                    paintShapeGlyph(canvas, size, color, shape),
                on: _tool == .shape && _penShape == shape,
                onTap: () {
                  final again = _tool == .shape && _penShape == shape;
                  setState(() => _penShape = shape);
                  _takeUp(again ? .select : .shape);
                },
              ),
          ],
        ),
      };

  static String _edgeStyleLabel(L l, MindmapEdgeStyle style) =>
      switch ((style.line, style.arrows)) {
        (MindmapLines.dashed, MindmapArrows.end) => l.mindmapEdgeDashedArrow,
        (MindmapLines.dashed, _) => l.mindmapEdgeDashed,
        (MindmapLines.dotted, _) => l.mindmapEdgeDotted,
        (_, MindmapArrows.both) => l.mindmapEdgeBothArrows,
        (_, MindmapArrows.end || MindmapArrows.start) => l.mindmapEdgeArrow,
        _ => l.mindmapEdgeLine,
      };

  static String _penShapeLabel(L l, MindmapPenShape shape) => switch (shape) {
    .rectangle => l.mindmapShapeRectangle,
    .ellipse => l.mindmapShapeEllipse,
    .triangle => l.mindmapShapeTriangle,
    .diamond => l.mindmapShapeDiamond,
    .line => l.mindmapEdgeLine,
    .arrow => l.mindmapEdgeArrow,
  };

  /// A stroke was drawn: on the map at once, written meanwhile.
  void _drew(List<Offset> points, MindmapPenShape? drawnAs) {
    final shape = drawnAs == null ? null : penShapeName(drawnAs);
    // As thick on the map as it was on screen.
    final width = math.max(1, (_penWidth / _camera.scale).round());
    // As the ViewModel will keep it: the same points, so the map's own is known.
    final stroke = strokeOf(points, width.toDouble());
    final shown = MindmapNode(
      id: '$_strokeDraft${_strokeCount++}',
      ownerId: '',
      version: 0,
      pageId: widget.pageId,
      kind: MindmapKinds.drawing,
      x: stroke.bounds.left.round(),
      y: stroke.bounds.top.round(),
      width: math.max(1, stroke.bounds.width.round()),
      height: math.max(1, stroke.bounds.height.round()),
      layer: (_state?.map ?? .empty).topLayer,
      text: '',
      color: _penColor,
      shape: shape,
      points: stroke.points,
      strokeWidth: width,
    );
    setState(() {
      // Those the map has by now are drawn by it.
      final map = _state?.map;
      _strokes
        ..removeWhere(
          (held) =>
              map?.nodes.any((node) => node.points == held.points) ?? false,
        )
        ..add(shown);
    });
    unawaited(
      _viewModel.draw(points, color: _penColor, width: width, shape: shape),
    );
  }

  static const _strokeDraft = 'mindmap-stroke-';

  /// The whole map — what "Show everything" shows — as a picture, saved where the
  /// person chooses: a download in the browser.
  Future<void> _savePicture() async {
    final state = _state;
    if (state == null) return;
    final l = L.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final draw = mindmapDrawingOf(context);
    // Drawing waits for the pictures in the map: a moment that is seen, and in which
    // the map is not changed under it.
    final wait = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _PictureWait(),
    );
    unawaited(navigator.push(wait));
    final Uint8List bytes;
    try {
      bytes = await draw((
        title: state.page.title,
        map: state.map,
        members: state.members,
        targets: state.targets,
      ));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.mindmapPictureFailed)));
      return;
    } finally {
      if (wait.isActive) navigator.removeRoute(wait);
    }
    if (!await saveArchive('${fileName(state.page.title)}$_png', bytes)) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.mindmapPictureSaved)));
  }

  Future<void> _choosePenColor() async {
    final chosen = await showMindmapColorSheet(
      context,
      current: _penColor,
      recent: _state?.ownColors ?? const [],
    );
    if (chosen != null && mounted) setState(() => _penColor = chosen.color);
  }

  Future<void> _chooseEdgeColor() async {
    final chosen = await showMindmapColorSheet(
      context,
      current: _edgeColor,
      recent: _state?.ownColors ?? const [],
    );
    if (chosen != null && mounted) setState(() => _edgeColor = chosen.color);
  }

  /// The colour new connections are drawn in: the one chosen, or the theme's line.
  Color _edgeInk(BuildContext context) =>
      switch (MindmapColor.parse(_edgeColor)) {
        final MindmapColor chosen => MindmapPaint.swatchOf(context, chosen),
        null => context.scheme.onSurface,
      };

  /// The pen's colour as it draws on this canvas: the one chosen, or the theme's ink.
  Color _penInk(BuildContext context) =>
      switch (MindmapColor.parse(_penColor)) {
        final MindmapColor chosen => MindmapPaint.swatchOf(context, chosen),
        null => context.scheme.onSurface,
      };

  /// A resized element: a snippet of text wraps at the new width and is just as
  /// large as its text then.
  void _resize(MindmapNode node, ({int width, int height}) size) {
    final box = node.kind == MindmapKinds.plain
        ? _plainBox(node.text, node.textSize, wrap: size.width.toDouble())
        : size;
    unawaited(_viewModel.resize(node, width: box.width, height: box.height));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    ref
      ..listen<List<MindmapHit>?>(
        mindmapViewModelProvider(widget.pageId)
            .select((state) => state.value?.hits),
        _hitsChanged,
      )
      ..listen<Mindmap?>(
        mindmapViewModelProvider(widget.pageId)
            .select((state) => state.value?.map),
        (_, map) => _arrived(map),
      )
      ..listen<bool?>(
        mindmapViewModelProvider(widget.pageId)
            .select((state) => state.value?.writable),
        _writableChanged,
      );
    final header = PageHeader(title: '', onBack: _back);
    // A link's target opens in the app's frame, under this screen: the map makes way.
    return LeaveForTarget(
      leave: _back,
      child: ref
          .watch(mindmapViewModelProvider(widget.pageId))
          .when(
            skipLoadingOnReload: true,
            loading: () => HiwiskiPage.loading(header: header),
            error: (error, _) => HiwiskiPage.error(
              header: header,
              error: error,
              onRetry: () =>
                  ref.invalidate(mindmapViewModelProvider(widget.pageId)),
            ),
            data: (state) {
              // The page itself is gone — deleted, or no longer shared.
              if (state == null) {
                return HiwiskiPage(
                  header: header,
                  body: EmptyState(
                    icon: HiwiskiSymbols.hub,
                    message: l.stateGone,
                  ),
                );
              }
              final editing = _editable;
              final wide = !Breakpoint.of(context).isCompact;
              final hits = _searching ? state.hits : const <MindmapHit>[];
              final current = hits.isEmpty
                  ? null
                  : hits[_hit.clamp(0, hits.length - 1)];
              // A selection whose element is gone — deleted here or elsewhere — is
              // none.
              final selection = switch (_selection) {
                final MindmapSelection chosen
                    when chosen.edge
                        ? state.map.edge(chosen.id) != null
                        : state.map.node(chosen.id) != null =>
                  chosen,
                _ => null,
              };
              final shown =
                  selection ??
                  switch (current) {
                    final MindmapHit hit =>
                      hit.isEdge
                          ? MindmapSelection.edge(hit.id)
                          : MindmapSelection.node(hit.id),
                    null => null,
                  };
              // The conflict being decided — none once it is, here or elsewhere.
              final deciding = _deciding;
              final conflicts = deciding == null
                  ? null
                  : state.conflicts[deciding];
              final theirs = deciding == null ? null : state.map.node(deciding);
              final mine = theirs == null || conflicts == null
                  ? null
                  : mineOf(theirs, conflicts);
              final results = hits.isEmpty
                  ? null
                  : MindmapResults(
                      hits: hits,
                      current: _hit,
                      onTap: _showHit,
                      order: state.order,
                      descending: state.descending,
                      onOrder: (order, descending) {
                        setState(() => _hit = 0);
                        _viewModel.orderHits(
                          order: order,
                          descending: descending,
                        );
                      },
                    );
              // The snippet being written, as large as what is typed so far.
              final writing = switch (_writing) {
                (:final node, :final isNew) => () {
                  final box = _writingBox(
                    _typed.text.isEmpty ? l.mindmapPlainHint : _typed.text,
                    node.textSize,
                    isNew: isNew,
                    width: node.width,
                  );
                  return MindmapWriting(
                    node: node.changed(width: box.width, height: box.height),
                    isNew: isNew,
                    field: _TextField(
                      controller: _typed,
                      focus: _typing,
                      hint: l.mindmapPlainHint,
                    ),
                  );
                }(),
                null => null,
              };
              // As just written, while the map has the old one — or none yet.
              final held = switch (_held) {
                final MindmapNode held
                    when state.map.node(_heldAs ?? held.id) == _heldFrom =>
                  held,
                _ => null,
              };
              // Above the keyboard while it is written.
              final keyboard = MediaQuery.viewInsetsOf(context).bottom;
              if (writing != null && keyboard != _keyboard) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _camera.show(writing.node.bounds);
                });
              }
              _keyboard = keyboard;
              _camera.padding = _covered(
                context,
                results: results != null,
                deciding: conflicts != null,
              );
              final safe = MediaQuery.paddingOf(context);
              return Scaffold(
                backgroundColor: context.scheme.surface,
                body: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyF,
                      control: true,
                    ): _openSearch,
                    const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                        _openSearch,
                  },
                  child: Stack(
                    children: [
                      // The canvas under everything, to the screen's edges.
                      Positioned.fill(
                        // The keys act on the canvas alone: typed into the search,
                        // Backspace deletes a letter, not the selected element.
                        child: Focus(
                          focusNode: _keys,
                          autofocus: true,
                          onKeyEvent: _key,
                          child: MindmapMembers(
                            members: state.members,
                            child: MindmapCanvas(
                              key: MindmapKeys.canvas,
                              state: state,
                              camera: _camera,
                              editing: editing,
                              selection: shown,
                              found: {for (final hit in hits) hit.id, ?_marked},
                              mine: mine,
                              writing: writing,
                              tool: _tool,
                              hideDrawings: _drawingsHidden,
                              snap: state.snap,
                              grid: state.grid,
                              pen: (color: _penInk(context), width: _penWidth),
                              penShape: _penShape,
                              linkStyle: _tool == .connect ? _edgeStyle : null,
                              linkLook: (color: _edgeColor, width: _edgeWidth),
                              onDraw: _drew,
                              onErase: (ids) => unawaited(
                                _viewModel.erase([
                                  for (final id in ids) ?state.map.node(id),
                                ]),
                              ),
                              held: [
                                ?held,
                                // Drawn, and not yet back from the database.
                                for (final stroke in _strokes)
                                  if (!state.map.nodes.any(
                                    (node) => node.points == stroke.points,
                                  ))
                                    stroke,
                              ],
                              labels: mine == null
                                  ? null
                                  : (
                                      mine: l.conflictMine,
                                      theirs: l.conflictTheirs,
                                    ),
                              onSelect: _select,
                              onOpen: (node) => unawaited(_open(node)),
                              onMove: (moves) =>
                                  unawaited(_viewModel.move(moves)),
                              group: {
                                for (final id in _group)
                                  if (state.map.node(id) != null) id,
                              },
                              onGroup: _grouped,
                              onResize: _resize,
                              onRotate: (node, rotation) => unawaited(
                                _viewModel.setRotation(node, rotation),
                              ),
                              onConnect: (from, to) => unawaited(
                                _viewModel.connect(
                                  from,
                                  to,
                                  line: _edgeStyle.line,
                                  arrows: _edgeStyle.arrows,
                                  color: _edgeColor,
                                  strokeWidth: _edgeWidth,
                                ),
                              ),
                              onDrop: (kind, at) => unawaited(_place(kind, at)),
                              onReady: _ready,
                            ),
                          ),
                        ),
                      ),
                      if (state.map.isEmpty)
                        IgnorePointer(
                          child: Center(
                            child: Padding(
                              padding: const .all(HiwiskiMetrics.space24),
                              child: Text(
                                editing ? l.mindmapToolsHint : l.mindmapEmpty,
                                textAlign: .center,
                                style: context.texts.bodyMedium?.copyWith(
                                  color: context.scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Over it at the top: the header with the search, offline and
                      // conflicts.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Column(
                            crossAxisAlignment: .stretch,
                            children: [
                              _Header(
                                title: state.page.title,
                                onBack: _back,
                                searching: _searching,
                                onSearch: _toggleSearch,
                                field: _SearchField(
                                  controller: _search,
                                  focus: _searchFocus,
                                  count: state.hits.length,
                                  onChanged: _query,
                                  onNext: () => _showHit(_hit + 1),
                                  onPrevious: () => _showHit(_hit - 1),
                                  onClose: _toggleSearch,
                                  withSteps: wide,
                                ),
                                // On a phone the search takes the whole line:
                                // the buttons beside it left the field too little
                                // room to show what was typed, and pushed its
                                // close button out of reach.
                                hideActions: !wide && _searching,
                                actions: [
                                  if (state.conflicts.isNotEmpty)
                                    TextButton.icon(
                                      key: MindmapKeys.conflicts,
                                      onPressed: _showConflicts,
                                      icon: const Icon(HiwiskiSymbols.merge),
                                      label: Text(
                                        l.mindmapConflicts(
                                          state.conflicts.length,
                                        ),
                                      ),
                                    ),
                                  // Editing: the way back and forth, and done —
                                  // seeing and drawing are in the corner then.
                                  if (editing) ...[
                                    IconButton(
                                      key: MindmapKeys.undo,
                                      tooltip: l.mindmapUndo,
                                      icon: const Icon(HiwiskiSymbols.undo),
                                      onPressed: state.canUndo
                                          ? () => unawaited(_viewModel.undo())
                                          : null,
                                    ),
                                    IconButton(
                                      key: MindmapKeys.redo,
                                      tooltip: l.mindmapRedo,
                                      icon: const Icon(HiwiskiSymbols.redo),
                                      onPressed: state.canRedo
                                          ? () => unawaited(_viewModel.redo())
                                          : null,
                                    ),
                                    _EditButton(
                                      editing: true,
                                      compact: !wide,
                                      onPressed: _toggleEditing,
                                    ),
                                  ] else ...[
                                    // Only where there is something drawn to hide.
                                    if (state.map.nodes.any(
                                      (node) =>
                                          node.kind == MindmapKinds.drawing,
                                    ))
                                      IconButton(
                                        key: MindmapKeys.drawings,
                                        tooltip: _drawingsHidden
                                            ? l.mindmapDrawingsShow
                                            : l.mindmapDrawingsHide,
                                        isSelected: _drawingsHidden,
                                        icon: const Icon(HiwiskiSymbols.draw),
                                        selectedIcon: const Icon(
                                          HiwiskiSymbols.visibilityOff,
                                        ),
                                        onPressed: _toggleDrawings,
                                      ),
                                    IconButton(
                                      key: MindmapKeys.fit,
                                      tooltip: l.mindmapFit,
                                      icon: const Icon(
                                        HiwiskiSymbols.fitScreen,
                                      ),
                                      onPressed: () => _camera.fit(
                                        state.map.bounds,
                                        glide: true,
                                      ),
                                    ),
                                    if (state.map.nodes.isNotEmpty)
                                      IconButton(
                                        key: MindmapKeys.picture,
                                        tooltip: l.mindmapPicture,
                                        icon: const Icon(
                                          HiwiskiSymbols.download,
                                        ),
                                        onPressed: () =>
                                            unawaited(_savePicture()),
                                      ),
                                    if (state.writable)
                                      _EditButton(
                                        editing: false,
                                        compact: !wide,
                                        onPressed: _toggleEditing,
                                      ),
                                  ],
                                ],
                              ),
                              if (!wide &&
                                  _searching &&
                                  _search.text.trim().isNotEmpty)
                                _SearchSteps(
                                  count: state.hits.length,
                                  onNext: () => _showHit(_hit + 1),
                                  onPrevious: () => _showHit(_hit - 1),
                                ),
                              SyncBanner(onMindmap: _fromBanner),
                            ],
                          ),
                        ),
                      ),
                      if (wide && results != null)
                        Positioned(
                          right: safe.right + HiwiskiMetrics.space8,
                          top: _camera.padding.top + HiwiskiMetrics.space8,
                          bottom: _camera.padding.bottom - safe.bottom,
                          width: HiwiskiMetrics.mindmapResultsWidth,
                          child: _Panel(child: results),
                        ),
                      // Over it at the bottom: the hits on a phone, the conflict being
                      // decided or what can be done with the selection, the tools.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Column(
                          mainAxisSize: .min,
                          crossAxisAlignment: .stretch,
                          children: [
                            if (!wide && results != null)
                              SizedBox(
                                height: HiwiskiMetrics.mindmapPreviewMinHeight,
                                child: _Panel(child: results),
                              ),
                            if (conflicts != null)
                              MindmapConflictBar(
                                conflicts: conflicts,
                                onMap: mine != null,
                                targetLabel: state.labelOfTarget,
                                onMine: () =>
                                    unawaited(_decided(conflicts, mine: true)),
                                onTheirs: () =>
                                    unawaited(_decided(conflicts, mine: false)),
                                onClose: () => setState(() => _deciding = null),
                                bottom: !editing,
                              )
                            else if (!wide && results != null)
                              SizedBox(height: safe.bottom),
                          ],
                        ),
                      ),
                      // Editing: the corner — what is added, drawn and done with a
                      // finger, or what can be done with what is selected.
                      // In the very corner: its background reaches into the safe
                      // area, its buttons keep out of it.
                      if (editing && conflicts == null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: MindmapCorner(
                            compact: !wide,
                            backKey: MindmapKeys.closeMenu,
                            backLabel: l.mindmapBack,
                            menus: _menus(state),
                            open: _menu,
                            onOpen: _openMenu,
                            submenu: _submenuOf(l, state),
                            onBack: _cornerBack,
                            selection: switch ((selection, _group)) {
                              (final MindmapSelection selected, _) =>
                                _selectionOptions(state, selected),
                              (_, final group) when group.isNotEmpty =>
                                _groupOptions(state, [
                                  for (final id in group) ?state.map.node(id),
                                ]),
                              _ => null,
                            },
                            onRelease: () => _select(null),
                            releaseKey: MindmapKeys.release,
                            releaseLabel: l.mindmapRelease,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}

/// The header over the canvas: no background of its own — the back button, the title,
/// the search and the actions each stand on a small surface just as large as they are,
/// so the map shows around them and they stay readable over it.
///
/// The search grows out of its button to the line's end: on a wide screen beside the
/// title, on a phone in its place.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onBack,
    required this.searching,
    required this.onSearch,
    required this.field,
    required this.actions,
    this.hideActions = false,
  });

  final String title;
  final VoidCallback onBack;
  final bool searching;

  /// Whether the actions make room for the search.
  final bool hideActions;

  /// Opens the search, or closes it.
  final VoidCallback onSearch;

  /// The open search: the words, the count, the way from hit to hit.
  final Widget field;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final compact = Breakpoint.of(context).isCompact;
    final style = context.texts.titleMedium;
    // As wide as the title needs: what is left goes to the search, or lies free
    // between the title and the buttons, which stand at the line's end.
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final needed = painter.width.ceilToDouble() + 2 * HiwiskiMetrics.space16;
    painter.dispose();
    return Padding(
      padding: const .all(HiwiskiMetrics.space8),
      child: Row(
        children: [
          _Surface(
            child: IconButton(
              key: MindmapKeys.back,
              tooltip: l.mindmapBack,
              icon: const Icon(HiwiskiSymbols.arrowBack),
              onPressed: onBack,
            ),
          ),
          const SizedBox(width: HiwiskiMetrics.space8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final room = constraints.maxWidth;
                const button = HiwiskiMetrics.minTapTarget;
                const gap = HiwiskiMetrics.space8;
                // Open, the search takes the line: on a phone the title's place
                // too.
                final titleRoom = switch ((searching, compact)) {
                  (false, _) => room - button - gap,
                  (true, true) => 0.0,
                  (true, false) => math.min(
                    HiwiskiMetrics.mindmapTitleWhileSearching,
                    room / 2,
                  ),
                };
                final titleWidth = math.max(0.0, math.min(needed, titleRoom));
                final searchWidth = searching
                    ? room - (titleWidth > 0 ? titleWidth + gap : 0)
                    : button;
                return Row(
                  mainAxisAlignment: .spaceBetween,
                  children: [
                    // Never wider than the room left: shrinking as the buttons
                    // beside it grow, it was wider for a moment and ran over.
                    Flexible(
                      child: AnimatedContainer(
                        duration: _grow,
                        curve: Curves.easeOutCubic,
                        width: titleWidth,
                        height: button,
                        child: _Surface(
                          child: Padding(
                            padding: const .symmetric(
                              horizontal: HiwiskiMetrics.space16,
                            ),
                            child: Align(
                              alignment: .centerLeft,
                              child: Text(
                                title,
                                maxLines: 1,
                                softWrap: false,
                                overflow: .ellipsis,
                                style: style,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Never wider than the line: closing on a phone, the buttons
                    // come back at once while the field still shrinks.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: room),
                      child: AnimatedContainer(
                        duration: _grow,
                        curve: Curves.easeOutCubic,
                        width: searchWidth,
                        // A line's height: the field inside lays out at the full
                        // width, and needs a bound for its height too.
                        height: button,
                        child: _Surface(
                          child: searching
                              // Laid out at its full width from the start and
                              // uncovered as the surface grows from the button.
                              ? OverflowBox(
                                  alignment: .centerRight,
                                  minWidth: searchWidth,
                                  maxWidth: searchWidth,
                                  child: field,
                                )
                              : IconButton(
                                  key: MindmapKeys.search,
                                  tooltip: l.mindmapSearch,
                                  icon: const Icon(HiwiskiSymbols.search),
                                  onPressed: onSearch,
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (!hideActions) ...[
            const SizedBox(width: HiwiskiMetrics.space8),
            _Surface(
              child: Row(mainAxisSize: .min, children: actions),
            ),
          ],
        ],
      ),
    );
  }

  static const _grow = Duration(milliseconds: 220);
}

/// A surface just as large as what is on it, over the canvas.
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: context.scheme.surfaceContainerHigh.withValues(
      alpha: mindmapOverlayOpacity,
    ),
    shape: const StadiumBorder(),
    clipBehavior: .antiAlias,
    child: child,
  );
}

/// The list of hits, on a card over the canvas.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    elevation: HiwiskiMetrics.elevationMenu,
    borderRadius: const .all(.circular(HiwiskiMetrics.radiusCard)),
    clipBehavior: .antiAlias,
    child: child,
  );
}

/// The open search in the header: the words, how many were found, the way from hit
/// to hit — also with Enter — and closing it.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.count,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.withSteps,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int count;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  /// Whether the count and the way from hit to hit stand in the field's line — not
  /// on a phone, where they have a line of their own ([_SearchSteps]).
  final bool withSteps;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Padding(
      padding: const .only(left: HiwiskiMetrics.space16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: MindmapKeys.searchField,
              controller: controller,
              focusNode: focus,
              textInputAction: .search,
              onChanged: onChanged,
              onSubmitted: (_) => onNext(),
              decoration: InputDecoration(
                hintText: l.mindmapSearch,
                // Every border: the theme's outlined ones stood in for the plain.
                border: .none,
                enabledBorder: .none,
                focusedBorder: .none,
                isDense: true,
              ),
            ),
          ),
          if (withSteps) ...[
            if (controller.text.trim().isNotEmpty)
              Text(l.mindmapSearchCount(count), style: context.texts.bodySmall),
            _StepButtons(count: count, onNext: onNext, onPrevious: onPrevious),
          ],
          IconButton(
            key: MindmapKeys.search,
            tooltip: l.mindmapSearchClose,
            icon: const Icon(HiwiskiSymbols.searchOff),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// On a phone, below the header: how many hits there are and the way from one to
/// the next.
class _SearchSteps extends StatelessWidget {
  const _SearchSteps({
    required this.count,
    required this.onNext,
    required this.onPrevious,
  });

  final int count;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(horizontal: HiwiskiMetrics.space8),
    child: Align(
      alignment: .centerRight,
      child: _Surface(
        child: Padding(
          padding: const .only(left: HiwiskiMetrics.space16),
          child: Row(
            mainAxisSize: .min,
            children: [
              Text(
                L.of(context).mindmapSearchCount(count),
                key: MindmapKeys.searchCount,
                style: context.texts.bodySmall,
              ),
              _StepButtons(
                count: count,
                onNext: onNext,
                onPrevious: onPrevious,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The way to the previous hit and the next.
class _StepButtons extends StatelessWidget {
  const _StepButtons({
    required this.count,
    required this.onNext,
    required this.onPrevious,
  });

  final int count;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Row(
      mainAxisSize: .min,
      children: [
        IconButton(
          key: MindmapKeys.searchPrevious,
          tooltip: l.mindmapSearchPrevious,
          icon: const Icon(HiwiskiSymbols.expandLess),
          onPressed: count == 0 ? null : onPrevious,
        ),
        IconButton(
          key: MindmapKeys.searchNext,
          tooltip: l.mindmapSearchNext,
          icon: const Icon(HiwiskiSymbols.expandMore),
          onPressed: count == 0 ? null : onNext,
        ),
      ],
    );
  }
}

/// The field a snippet of text is written in on the canvas: in the snippet's own
/// style and colour, no frame of its own — it looks as it will once written.
class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.focus,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    return TextField(
      key: MindmapKeys.textField,
      controller: controller,
      focusNode: focus,
      style: style,
      cursorColor: style.color,
      maxLines: null,
      keyboardType: .multiline,
      textCapitalization: .sentences,
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: .zero,
        // Every border, not only the plain one: the theme's outlined ones stood in
        // for it, kept a gap at each side of the text, and the last word broke onto
        // a line the snippet cut off.
        border: .none,
        enabledBorder: .none,
        focusedBorder: .none,
        hintText: hint,
        hintStyle: style.copyWith(
          color: style.color?.withValues(alpha: _hintOpacity),
        ),
      ),
    );
  }

  static const _hintOpacity = 0.5;
}

/// "Edit" in the header — and, while editing, "Done": on a phone its symbol alone.
class _EditButton extends StatelessWidget {
  const _EditButton({
    required this.editing,
    required this.compact,
    required this.onPressed,
  });

  final bool editing;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final label = editing ? l.mindmapDone : l.mindmapEdit;
    final icon = Icon(editing ? HiwiskiSymbols.check : HiwiskiSymbols.edit);
    if (compact) {
      return editing
          ? IconButton.filled(
              key: MindmapKeys.edit,
              tooltip: label,
              icon: icon,
              onPressed: onPressed,
            )
          : IconButton(
              key: MindmapKeys.edit,
              tooltip: label,
              icon: icon,
              onPressed: onPressed,
            );
    }
    return Padding(
      padding: const .symmetric(horizontal: HiwiskiMetrics.space4),
      child: editing
          ? FilledButton.icon(
              key: MindmapKeys.edit,
              onPressed: onPressed,
              icon: icon,
              label: Text(label),
            )
          : FilledButton.tonalIcon(
              key: MindmapKeys.edit,
              onPressed: onPressed,
              icon: icon,
              label: Text(label),
            ),
    );
  }
}

/// While the picture is drawn: what is happening, not a frozen screen.
class _PictureWait extends StatelessWidget {
  const _PictureWait();

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: MindmapKeys.pictureWait,
    content: Row(
      children: [
        const SizedBox.square(
          dimension: HiwiskiMetrics.icon24,
          child: CircularProgressIndicator(),
        ),
        const SizedBox(width: HiwiskiMetrics.space16),
        Expanded(child: Text(L.of(context).mindmapPictureWait)),
      ],
    ),
  );
}

/// A picture's file ending.
const _png = '.png';

/// The levels below a choice in the corner: the kinds of connections, the shapes.
enum _Submenu { edges, shapes, align }

/// The names of the group's commands that are not an alignment.
const _spreadAcross = 'spreadAcross';
const _spreadDown = 'spreadDown';
const _sameWidth = 'sameWidth';
const _sameHeight = 'sameHeight';
const _sameSize = 'sameSize';

/// Spreading out takes a first, a last and one between.
const _spreadAtLeast = 3;

/// The corner's menus, in their order.
const _addMenu = 0;
const _drawMenu = 1;
const _toolsMenu = 2;
