import 'package:flutter/material.dart';
import 'package:hiwiski/core/ui/edit_actions.dart';
import 'package:hiwiski/domain/wiki/wiki_page.dart';
import 'package:hiwiski/features/wiki/page/view/page_actions.dart';
import 'package:hiwiski/features/wiki/page/view/page_screen.dart';

/// A wiki page with what the wiki's screen puts around it: the buttons the page
/// reports — "Edit", and "Cancel" and "Save" while editing — above it, as its header
/// shows them.
class PageHost extends StatefulWidget {
  const PageHost({super.key, required this.page});

  final WikiPage page;

  @override
  State<PageHost> createState() => _PageHostState();
}

class _PageHostState extends State<PageHost> {
  final _actions = PageActions();

  @override
  void dispose() {
    _actions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      ListenableBuilder(
        listenable: _actions,
        builder: (context, _) {
          final onEdit = _actions.onEdit;
          final onDone = _actions.onDone;
          final onCancel = _actions.onCancel;
          if (!_actions.writable ||
              onEdit == null ||
              onDone == null ||
              onCancel == null) {
            return const SizedBox.shrink();
          }
          return Align(
            alignment: .centerRight,
            child: EditActions(
              editing: _actions.editing,
              onEdit: onEdit,
              onSave: onDone,
              onCancel: onCancel,
            ),
          );
        },
      ),
      Expanded(
        child: PageScreen(page: widget.page, actions: _actions),
      ),
    ],
  );
}
