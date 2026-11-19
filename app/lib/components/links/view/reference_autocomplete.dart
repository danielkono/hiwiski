import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/keyboard_bar.dart';
import '../../../core/ui/text_insertion.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/links/reference_completion.dart';
import '../links_view_model.dart';
import 'link_chip.dart';

/// Suggestions while typing **`#` and a key** — number and title, right at the cursor.
///
/// Wraps any text field that may hold references: page text, task description, event
/// note, comment. A tap, Enter or Tab puts `#TD-14` in place of what was typed (or the
/// address, for an item that has no number yet); the arrow keys move through the list,
/// Escape closes it. Without it a reference meant knowing the number by heart or leaving
/// the text for the link picker.
///
/// Where the list opens:
///
/// - **Above the keyboard on the screen** (phone, tablet): docked over the full width,
///   the best match nearest the keyboard, the line being typed scrolled up out from under
///   it. Next to the line it would be hidden — the cursor sits just above the keyboard
///   while typing, and the keyboard covers whatever opens below.
/// - Otherwise **under the line being typed**, not under the field: in a page of forty
///   lines, a list below the field is out of sight. Where there is no room below — the
///   last lines of the window — it opens above the line instead.
class ReferenceAutocomplete extends ConsumerStatefulWidget {
  const ReferenceAutocomplete({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.child,
    this.dockedBelow = 0,
    this.indentWithTab = false,
  });

  /// Whether Tab pushes the line in (and Shift+Tab back) while no list is open — for a
  /// text written in Markdown, where that is how a list is nested. Elsewhere Tab keeps
  /// moving on to the next field.
  final bool indentWithTab;

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The text field — built with [controller] and [focusNode].
  final Widget child;

  /// What else is docked above the keyboard, below the suggestions — the insert bar of
  /// the page editor ([KeyboardBar.height]).
  final double dockedBelow;

  @override
  ConsumerState<ReferenceAutocomplete> createState() =>
      _ReferenceAutocompleteState();
}

class _ReferenceAutocompleteState extends ConsumerState<ReferenceAutocomplete>
    with WidgetsBindingObserver {
  static const double _width = HiwiskiMetrics.suggestionWidth;
  static const double _rowHeight = HiwiskiMetrics.listRowHeight;

  /// Rows the docked list shows at once — more would leave too little of the text.
  static const int _dockedRows = 3;

  final _link = LayerLink();
  final _portal = OverlayPortalController();
  ReferenceQuery? _query;
  List<LinkItem> _options = const [];
  int _highlighted = 0;

  /// Where the list hangs, relative to the field: under (or above) the caret's line.
  Offset _anchor = .zero;

  /// The list opens above the caret's line — there is no room below it.
  bool _above = false;

  /// The room the list has next to the caret's line.
  double _maxHeight = .infinity;

  /// Docked above the keyboard on the screen instead of next to the line.
  bool _docked = false;

  /// Escape closes the list until the query changes.
  ReferenceQuery? _dismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_update);
    widget.focusNode.addListener(_update);
  }

  @override
  void didUpdateWidget(ReferenceAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_update);
      widget.focusNode.addListener(_update);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_update);
    widget.focusNode.removeListener(_update);
    super.dispose();
  }

  /// The keyboard comes and goes, the window turns: the list moves along.
  @override
  void didChangeMetrics() {
    if (_open) _update();
  }

  bool get _open => _options.isNotEmpty;

  /// The list runs from the bottom up — docked, or above the line: index 0 is the row
  /// nearest the text.
  bool get _bottomUp => _docked || _above;

  void _update() {
    final query = widget.focusNode.hasFocus
        ? referenceQueryAt(widget.controller.value)
        : null;
    final dismissed = switch ((query, _dismissed)) {
      (final query?, final gone?) =>
        gone.start == query.start && gone.text == query.text,
      _ => false,
    };
    final options = query == null || dismissed
        ? const <LinkItem>[]
        : completeReference(ref.read(linksViewModelProvider).items, query.text);
    if (!mounted) return;
    setState(() {
      if (query?.start != _query?.start) _highlighted = 0;
      _query = query;
      _options = options;
      _highlighted = options.isEmpty
          ? 0
          : _highlighted.clamp(0, options.length - 1);
    });
    if (options.isEmpty) {
      _portal.hide();
      return;
    }
    // The caret's place is known only once the new text is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _options.isEmpty) return;
      if (typesOnScreen() && keyboardHeightOf(context) > 0) {
        if (!_docked) setState(() => _docked = true);
        _portal.show();
        _revealCaret();
      } else {
        _placeAtCaret();
        _portal.show();
      }
    });
  }

  RenderEditable? get _editable {
    final editable = widget.focusNode.context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.renderEditable;
    return editable != null && editable.attached ? editable : null;
  }

  /// Under the caret's line, or above it when there is more room there — in the field's
  /// coordinates, clamped so the list does not stick out on the right.
  void _placeAtCaret() {
    final query = _query;
    final field = context.findRenderObject() as RenderBox?;
    final editable = _editable;
    if (query == null || field == null || editable == null) return;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: query.start),
    );
    final top = editable.localToGlobal(caret.topLeft);
    final bottom = editable.localToGlobal(caret.bottomLeft);

    final window = MediaQueryData.fromView(View.of(context));
    const gap = HiwiskiMetrics.space4 + HiwiskiMetrics.space8;
    final roomBelow =
        window.size.height -
        math.max(window.viewInsets.bottom, window.padding.bottom) -
        bottom.dy -
        gap;
    final roomAbove = top.dy - window.padding.top - gap;
    final needed = _options.length * _rowHeight + 2 * HiwiskiMetrics.space4;
    final above = roomBelow < needed && roomAbove > roomBelow;

    final local = field.globalToLocal(above ? top : bottom);
    final maxX = math.max(0.0, field.size.width - _width);
    final anchor = Offset(local.dx.clamp(0.0, maxX), local.dy);
    final maxHeight = math.max(_rowHeight, above ? roomAbove : roomBelow);
    if (anchor != _anchor ||
        above != _above ||
        maxHeight != _maxHeight ||
        _docked) {
      setState(() {
        _anchor = anchor;
        _above = above;
        _maxHeight = maxHeight;
        _docked = false;
      });
    }
  }

  /// The docked list covers the lines just above the keyboard — where the cursor is
  /// while typing. The line being typed moves up out from under it.
  void _revealCaret() {
    final query = _query;
    final editable = _editable;
    if (query == null || editable == null) return;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: query.start),
    );
    final covered =
        math.min(_options.length, _dockedRows) * _rowHeight +
        HiwiskiMetrics.space8;
    editable.showOnScreen(
      rect: Rect.fromLTRB(
        caret.left,
        caret.top,
        caret.right,
        caret.bottom + covered,
      ),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  void _choose(LinkItem item) {
    final query = _query;
    if (query == null) return;
    widget.controller.value = applyReference(
      widget.controller.value,
      query,
      item,
    );
    widget.focusNode.requestFocus();
  }

  /// Down is down on the screen — in a list that runs from the bottom up, toward the
  /// text.
  void _move(int delta) {
    if (!_open) return;
    final step = _bottomUp ? -delta : delta;
    setState(() => _highlighted = (_highlighted + step) % _options.length);
  }

  void _dismiss() {
    _dismissed = _query;
    _update();
  }

  @override
  Widget build(BuildContext context) {
    // Watched, so the index stays loaded while the field is on screen.
    ref.watch(linksViewModelProvider);
    // Only while the list is open do these keys belong to it — otherwise Enter is a new
    // line and the arrows move the cursor, as always.
    return Shortcuts(
      shortcuts: _open
          ? const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown): _MoveIntent(1),
              SingleActivator(LogicalKeyboardKey.arrowUp): _MoveIntent(-1),
              SingleActivator(LogicalKeyboardKey.enter): _ChooseIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): _ChooseIntent(),
              SingleActivator(LogicalKeyboardKey.tab): _ChooseIntent(),
              SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
            }
          : {
              if (widget.indentWithTab) ...const {
                SingleActivator(LogicalKeyboardKey.tab): _IndentIntent(),
                SingleActivator(LogicalKeyboardKey.tab, shift: true):
                    _IndentIntent(outdent: true),
              },
            },
      child: Actions(
        actions: {
          _IndentIntent: CallbackAction<_IndentIntent>(
            onInvoke: (intent) =>
                indentSelection(widget.controller, outdent: intent.outdent),
          ),
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) => _move(intent.delta),
          ),
          _ChooseIntent: CallbackAction<_ChooseIntent>(
            onInvoke: (_) => _open ? _choose(_options[_highlighted]) : null,
          ),
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) => _dismiss(),
          ),
        },
        child: CompositedTransformTarget(
          link: _link,
          // The root overlay spans the window — the docked list measures from its bottom.
          child: OverlayPortal(
            overlayLocation: .rootOverlay,
            controller: _portal,
            overlayChildBuilder: (context) {
              final rows = _Suggestions(
                options: _options,
                highlighted: _highlighted,
                bottomUp: _bottomUp,
                docked: _docked,
                onChoose: _choose,
              );
              return _docked
                  ? _DockedList(dockedBelow: widget.dockedBelow, child: rows)
                  : _FloatingList(
                      link: _link,
                      above: _above,
                      anchor: _anchor,
                      width: _width,
                      maxHeight: _maxHeight,
                      child: rows,
                    );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Under (or above) the text, where the `#` was typed.
class _FloatingList extends StatelessWidget {
  const _FloatingList({
    required this.link,
    required this.above,
    required this.anchor,
    required this.width,
    required this.maxHeight,
    required this.child,
  });

  final LayerLink link;
  final bool above;
  final Offset anchor;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final alignment = above ? Alignment.bottomLeft : Alignment.topLeft;
    return CompositedTransformFollower(
      link: link,
      targetAnchor: .topLeft,
      followerAnchor: alignment,
      offset:
          anchor +
          Offset(0, above ? -HiwiskiMetrics.space4 : HiwiskiMetrics.space4),
      child: Align(
        alignment: alignment,
        // Part of the field as far as taps go: a tap on a suggestion must not take the
        // focus away first — the list would close before the tap arrives.
        child: TextFieldTapRegion(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
            child: Material(
              elevation: HiwiskiMetrics.elevationMenu,
              color: context.scheme.surfaceContainerHigh,
              borderRadius: const .all(.circular(HiwiskiMetrics.radiusMenu)),
              clipBehavior: .antiAlias,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Over the full width, right on top of the keyboard (and of whatever else is docked
/// there) — the row a thumb reaches without looking for it.
class _DockedList extends StatelessWidget {
  const _DockedList({required this.dockedBelow, required this.child});

  final double dockedBelow;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: keyboardHeightOf(context) + dockedBelow,
    child: TextFieldTapRegion(
      child: Material(
        color: context.scheme.surfaceContainerHigh,
        // The context is BoxBorder: abstract, a shorthand finds no constructor.
        // ignore: many_lints/prefer_shorthands_with_constructors
        shape: Border(top: BorderSide(color: context.scheme.outlineVariant)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight:
                _ReferenceAutocompleteState._dockedRows *
                _ReferenceAutocompleteState._rowHeight,
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// The suggestions — from the bottom up when the list sits above the text, so the
/// best match is the one nearest to it.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.options,
    required this.highlighted,
    required this.bottomUp,
    required this.docked,
    required this.onChoose,
  });

  final List<LinkItem> options;
  final int highlighted;
  final bool bottomUp;
  final bool docked;
  final ValueChanged<LinkItem> onChoose;

  @override
  Widget build(BuildContext context) => ListView(
    // A handful of rows under a maximum height: the list is as tall as they are.
    // ignore: many_lints/avoid_shrink_wrap_in_lists
    shrinkWrap: true,
    reverse: bottomUp,
    itemExtent: _ReferenceAutocompleteState._rowHeight,
    padding: docked
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(vertical: HiwiskiMetrics.space4),
    children: [
      for (final (index, item) in options.indexed)
        ListTile(
          dense: true,
          selected: index == highlighted,
          selectedTileColor: context.scheme.secondaryContainer,
          leading: Icon(
            linkItemIcon(item.itemType),
            size: HiwiskiMetrics.icon20,
          ),
          title: Text(item.title, maxLines: 1, overflow: .ellipsis),
          trailing: switch (item.entityKey) {
            null => null,
            final key => Text(key, style: context.tokens.text.monoSmall),
          },
          onTap: () => onChoose(item),
        ),
    ],
  );
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _ChooseIntent extends Intent {
  const _ChooseIntent();
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}

class _IndentIntent extends Intent {
  const _IndentIntent({this.outdent = false});

  final bool outdent;
}
