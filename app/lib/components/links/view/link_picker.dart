import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/states.dart';
import '../../../core/ui/ui_keys.dart';
import '../../../domain/links/link_text.dart';
import '../links_view_model.dart';
import 'link_chip.dart';

/// The **link picker**: type selection, search, and a tap inserts.
///
/// **It never inserts the number, but the address** `[Title](hiwiski://todo/<uuid>)`.
/// Otherwise an item just created offline could not be linked — and that is exactly the
/// common case: you create a task and write it into a wiki page in the same go.
///
/// The search runs **on the device**, not on the server: linking has to work offline,
/// otherwise the UUID form would be pointless.
Future<String?> showLinkPicker(BuildContext context) =>
    showHiwiskiSheet<String>(
      context: context,
      title: L.of(context).wikiLinkPick,
      builder: (context) => const _PickerBody(),
    );

class _PickerBody extends ConsumerStatefulWidget {
  const _PickerBody();

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  static const List<String> _types = [
    EntityTypes.todo,
    EntityTypes.todoList,
    EntityTypes.event,
    EntityTypes.wikiPage,
  ];

  final _input = TextEditingController();
  final _selected = <String>{};
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final index = ref.watch(linksViewModelProvider);

    final term = _query.trim().toLowerCase();
    // Nothing archived on offer: a new link goes to what is current.
    final hits =
        index.items
            .where((item) => !item.archived)
            .where(
              (item) => _selected.isEmpty || _selected.contains(item.itemType),
            )
            .where(
              (item) =>
                  term.isEmpty ||
                  item.title.toLowerCase().contains(term) ||
                  (item.entityKey?.toLowerCase().contains(term) ?? false),
            )
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        TextField(
          key: CoreKeys.linkSearch,
          controller: _input,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(HiwiskiSymbols.search),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: HiwiskiMetrics.space12),
        Wrap(
          spacing: HiwiskiMetrics.space8,
          children: [
            for (final type in _types)
              FilterChip(
                label: Text(linkItemTypeLabel(l, type)),
                avatar: Icon(linkItemIcon(type), size: HiwiskiMetrics.icon18),
                selected: _selected.contains(type),
                onSelected: (_) => setState(() {
                  if (!_selected.remove(type)) _selected.add(type);
                }),
              ),
          ],
        ),
        const SizedBox(height: HiwiskiMetrics.space8),
        if (hits.isEmpty)
          Padding(
            padding: const .symmetric(vertical: HiwiskiMetrics.space24),
            child: EmptyState(
              icon: HiwiskiSymbols.link,
              message: l.linkPickEmpty,
            ),
          )
        else
          // Capped: a sheet with four hundred rows is not a choice, it is a prompt to
          // use the search.
          for (final item in hits.take(30))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(linkItemIcon(item.itemType)),
              title: Text(item.title),
              subtitle: Text(linkItemTypeLabel(l, item.itemType)),
              trailing: switch (item.entityKey) {
                null => null,
                final key => Text(key, style: context.tokens.text.entityKey),
              },
              onTap: () => Navigator.of(context).pop(
                UriReference.markdown(item.itemType, item.itemId, item.title),
              ),
            ),
      ],
    );
  }
}
