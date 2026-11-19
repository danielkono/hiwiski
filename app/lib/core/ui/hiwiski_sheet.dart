import 'package:flutter/material.dart';

import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';

/// **Sheet or dialog — one component.**
///
/// "Every module can be shown as a full page and as an overlay, with the same
/// information. Large screens use a dialog for it, small ones a sheet from the
/// bottom. There is **one** component for it."
///
/// No `showDialog` in one place and `showModalBottomSheet` in another — in an earlier version
/// that was exactly why the same action looked different in two places.
Future<T?> showHiwiskiSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  List<Widget> Function(BuildContext context)? actions,
  bool dismissible = true,
  List<ChangeNotifier> owns = const [],
  double maxWidth = HiwiskiMetrics.dialogMaxWidth,
  bool scrolls = true,
}) {
  final compact = Breakpoint.of(context).isCompact;
  final content = _SheetBody(
    title: title,
    compact: compact,
    actions: actions,
    builder: builder,
    dismissible: dismissible,
    owns: owns,
    scrolls: scrolls,
  );

  if (compact) {
    return showModalBottomSheet<T>(
      context: context,
      // Over the whole screen, not in the areas' navigator inside the shell: there the
      // shade stopped short of the status bar and the tab bar, which stayed bright.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      builder: (context) => content,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (context) => Dialog(
      insetPadding: const .all(HiwiskiMetrics.space24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    ),
  );
}

/// The buttons of a sheet — **always at its bottom edge**, however long the content.
///
/// Put it anywhere in a sheet's body, where it has the state it needs (a "Save" that
/// reads the fields): it draws nothing there and hands its buttons to the sheet, which
/// shows them below the scrolling part. Before, "Save" sat at the end of the content, and
/// in a long event or an import one scrolled for it — or did not find it at all.
///
/// Outside a sheet (a body shown as a page of its own) the buttons stay where they are.
class SheetActions extends StatefulWidget {
  const SheetActions({super.key, required this.children});

  final List<Widget> children;

  @override
  State<SheetActions> createState() => _SheetActionsState();
}

class _SheetActionsState extends State<SheetActions> {
  // Borrowed from the sheet, which owns and disposes it; this only releases it.
  // ignore: many_lints/dispose_fields
  _SheetFooter? _footer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final footer = context
        .dependOnInheritedWidgetOfExactType<_SheetScope>()
        ?.footer;
    if (footer != _footer) {
      _footer?.release(this);
      _footer = footer;
    }
  }

  @override
  void dispose() {
    _footer?.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final footer = _footer;
    if (footer == null) return _ActionRow(children: widget.children);
    // Handed over after the frame: the footer is a sibling further down and must not be
    // marked dirty while the body is being built.
    final children = widget.children;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) footer.claim(this, children);
    });
    return const SizedBox.shrink();
  }
}

/// Who currently fills the footer, and with what.
class _SheetFooter extends ChangeNotifier {
  Object? _owner;
  List<Widget> children = const [];

  void claim(Object owner, List<Widget> next) {
    _owner = owner;
    children = next;
    notifyListeners();
  }

  void release(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    children = const [];
    // The sheet may be going away with its body — tell it after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }
}

class _SheetScope extends InheritedWidget {
  const _SheetScope({required this.footer, required super.child});

  final _SheetFooter footer;

  @override
  bool updateShouldNotify(_SheetScope oldWidget) => footer != oldWidget.footer;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A `Spacer` among the children puts what comes before it on the left — "Delete"
    // on the far side of "Cancel" and "Save".
    final split = children.indexWhere((child) => child is Spacer);
    final leading = split < 0 ? const <Widget>[] : children.sublist(0, split);
    final trailing = split < 0 ? children : children.sublist(split + 1);
    return SizedBox(
      width: .infinity,
      child: leading.isEmpty
          ? _ButtonGroup(buttons: trailing, alignment: .end)
          : Wrap(
              alignment: .spaceBetween,
              crossAxisAlignment: .center,
              runSpacing: HiwiskiMetrics.space8,
              children: [
                _ButtonGroup(buttons: leading, alignment: .start),
                _ButtonGroup(buttons: trailing, alignment: .end),
              ],
            ),
    );
  }
}

/// Buttons side by side; those that do not fit move to the next line instead of
/// running past the edge — "Keep mine" and "Take theirs" do not fit a phone in one.
class _ButtonGroup extends StatelessWidget {
  const _ButtonGroup({required this.buttons, required this.alignment});

  final List<Widget> buttons;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    crossAxisAlignment: .center,
    spacing: HiwiskiMetrics.space8,
    runSpacing: HiwiskiMetrics.space8,
    children: buttons,
  );
}

class _SheetBody extends StatefulWidget {
  const _SheetBody({
    required this.title,
    required this.compact,
    required this.builder,
    required this.dismissible,
    this.actions,
    this.owns = const [],
    this.scrolls = true,
  });

  final String title;
  final bool compact;
  final WidgetBuilder builder;
  final bool dismissible;
  final List<Widget> Function(BuildContext context)? actions;

  /// Controllers the caller made for the fields — disposed with the sheet.
  ///
  /// Not right after `await showHiwiskiSheet(...)`: the future completes on `pop`, while
  /// the sheet is still sliding out and its fields still listen. Disposed there, the
  /// closing keyboard hit a dead controller — a red screen after "Save".
  final List<ChangeNotifier> owns;

  /// Whether the sheet scrolls its body. Without, the body gets the sheet's full height
  /// and scrolls itself — pages side by side ([PageView]) each with a scroll position
  /// of their own, and a sheet that does not change its height with each page.
  final bool scrolls;

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  static const _bodyPadding = EdgeInsets.fromLTRB(
    HiwiskiMetrics.space20,
    HiwiskiMetrics.space8,
    HiwiskiMetrics.space20,
    HiwiskiMetrics.space20,
  );

  final _footer = _SheetFooter();

  @override
  void dispose() {
    _footer.dispose();
    for (final notifier in widget.owns) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(
            HiwiskiMetrics.space20,
            HiwiskiMetrics.space8,
            HiwiskiMetrics.space8,
            HiwiskiMetrics.space8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleLarge),
              ),
              if (widget.dismissible)
                IconButton(
                  icon: const Icon(HiwiskiSymbols.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
            ],
          ),
        ),
        Flexible(
          child: _SheetScope(
            footer: _footer,
            child: widget.scrolls
                ? SingleChildScrollView(
                    // Room at the top: a first text field's label floats above its
                    // border once it holds text — at 0 the scroll view cut it off.
                    padding: _bodyPadding,
                    child: Builder(builder: widget.builder),
                  )
                : Padding(
                    padding: _bodyPadding,
                    child: Builder(builder: widget.builder),
                  ),
          ),
        ),
        ListenableBuilder(
          listenable: _footer,
          builder: (context, _) {
            final footer = [
              ...?widget.actions?.call(context),
              ..._footer.children,
            ];
            return Padding(
              // Stay above the keyboard: without this, in a sheet it covers exactly the
              // field being typed into — and the buttons.
              padding: .only(bottom: keyboard),
              child: footer.isEmpty
                  ? const SizedBox.shrink()
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        // The context is BoxBorder: abstract, a shorthand finds no constructor.
                        // ignore: many_lints/prefer_shorthands_with_constructors
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const .fromLTRB(
                          HiwiskiMetrics.space20,
                          HiwiskiMetrics.space12,
                          HiwiskiMetrics.space20,
                          HiwiskiMetrics.space16,
                        ),
                        child: _ActionRow(children: footer),
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}
