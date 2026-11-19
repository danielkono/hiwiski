import 'package:flutter/material.dart';

import '../kanban_view_model.dart';
import 'kanban_board.dart';

/// A board's cards move for whoever may check off — or is assigned to the card.
class KanbanStateBoard extends StatelessWidget {
  const KanbanStateBoard({
    super.key,
    required this.state,
    required this.padding,
    this.preview = false,
  });

  final KanbanState state;
  final EdgeInsets padding;
  final bool preview;

  @override
  Widget build(BuildContext context) => KanbanBoard(
    list: state.list,
    columns: state.columns,
    cards: state.items,
    writable: state.writable,
    mayMove: state.mayCheckOff,
    members: state.members,
    padding: padding,
    preview: preview,
  );
}
