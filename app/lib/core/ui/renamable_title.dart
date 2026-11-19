import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'renamable_row.dart';

/// The title of a [RenamableRow]: [child] as it is, and while the row is edited a
/// field with [text], in [style] — the row keeps its place and its height.
class RenamableTitle extends StatelessWidget {
  const RenamableTitle({
    super.key,
    required this.text,
    required this.style,
    required this.child,
    this.fieldKey,
  });

  final String text;
  final TextStyle? style;
  final Widget child;

  /// The field's key — for the tests.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => RenamableRow.editing(context)
      ? _TitleField(key: fieldKey, text: text, style: style)
      : child;
}

class _TitleField extends StatefulWidget {
  const _TitleField({super.key, required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
  late final _controller = TextEditingController(
    text: widget.text,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.text.length);
  final _focus = FocusNode();

  /// Saved or given up once: Enter, Escape and the focus lost after them must not
  /// close it twice.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _close(save: true);
  }

  void _close({required bool save}) {
    if (_closed) return;
    _closed = true;
    final title = _controller.text.trim();
    final changed = save && title.isNotEmpty && title != widget.text;
    RenamableRow.maybeOf(context)?.close(changed ? title : null);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          _close(save: false),
    },
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      style: widget.style,
      textInputAction: .done,
      decoration: const InputDecoration.collapsed(hintText: null),
      onSubmitted: (_) => _close(save: true),
      onTapOutside: (_) => _focus.unfocus(),
    ),
  );
}
