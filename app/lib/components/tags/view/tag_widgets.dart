import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/common/wire.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/add_tag_chip.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../core/ui/tag_chips.dart';
import '../../../core/ui/tag_color_picker.dart';
import '../../../domain/tags/tag.dart';
import '../tags_view_model.dart';
import 'tags_keys.dart';

/// The tags of an item as a row of small chips — on cards and in rows.
class TagChips extends ConsumerWidget {
  const TagChips({super.key, required this.raw, this.dense = true});

  final String raw;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(tagsViewModelProvider)
      .when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        // A decoration on every row: no chips rather than an error line in each.
        error: (_, _) => const SizedBox.shrink(),
        data: (state) =>
            _TagChipsBody(dense: dense, raw: raw, known: state.byId),
      );
}

class _TagChipsBody extends StatelessWidget {
  const _TagChipsBody({
    required this.dense,
    required this.raw,
    required this.known,
  });

  final bool dense;
  final String raw;
  final Map<String, Tag> known;

  @override
  Widget build(BuildContext context) {
    final tags = [for (final id in tagIdsOf(raw)) ?known[id]];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: HiwiskiMetrics.space6,
      runSpacing: HiwiskiMetrics.space6,
      children: [for (final tag in tags) TagChip(tag: tag, dense: dense)],
    );
  }
}

/// Creates a tag: name and color. Returns the new id.
Future<String?> showNewTagDialog(
  BuildContext context,
  WidgetRef ref, {
  Tag? editing,
  String initialName = '',
}) async {
  final l = L.of(context);
  final name = TextEditingController(text: editing?.name ?? initialName);
  String color = editing?.colorToken ?? ColorTokens.blue;
  final result = await showHiwiskiSheet<(String, String)>(
    context: context,
    title: editing == null ? l.tagNew : l.tagEdit,
    owns: [name],
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: .stretch,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(labelText: l.tagName),
            onSubmitted: (value) =>
                Navigator.of(context).pop((value.trim(), color)),
          ),
          const SizedBox(height: HiwiskiMetrics.space16),
          TagColorPicker(
            selected: color,
            onSelected: (value) => setState(() => color = value),
          ),
        ],
      ),
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.actionCancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop((name.text.trim(), color)),
        child: Text(editing == null ? l.tagCreate : l.actionSave),
      ),
    ],
  );
  if (result == null || result.$1.isEmpty) return null;
  if (editing != null) {
    await ref
        .read(tagsViewModelProvider.notifier)
        .updateTag(editing, name: result.$1, colorToken: result.$2);
    return editing.id;
  }
  return createTagMutation.run(
    ref,
    (tsx) => tsx
        .get(tagsViewModelProvider.notifier)
        .createTag(result.$1, colorToken: result.$2),
  );
}

/// The picker sheet: a search on top, all tags with checkboxes, create, and **rename and
/// delete your own tags right here** — in an earlier version that only worked on the tags page, and
/// nobody finds their way there in the middle of creating something.
///
/// The search narrows the list by name; when nothing matches, "+ Tag" creates the tag
/// with what was typed. With thirty tags, scrolling for the one was the slow part.
Future<Set<String>?> showTagPicker(
  BuildContext context,
  Set<String> current,
) async {
  final chosen = {...current};
  final container = ProviderScope.containerOf(context, listen: false);
  final search = TextEditingController();
  final result = await showHiwiskiSheet<Set<String>>(
    context: context,
    title: L.of(context).tagsTitle,
    owns: [search],
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(tagsViewModelProvider).value;
        final all = state?.ranked ?? const <Tag>[];
        final me = state?.me;
        return StatefulBuilder(
          builder: (context, setState) {
            final term = search.text.trim().toLowerCase();
            final tags = term.isEmpty
                ? all
                : all
                      .where((tag) => tag.name.toLowerCase().contains(term))
                      .toList();
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                TextField(
                  key: TagKeys.tagSearch,
                  controller: search,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: L.of(context).tagSearch,
                    prefixIcon: const Icon(
                      HiwiskiSymbols.search,
                      size: HiwiskiMetrics.icon20,
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  // Enter takes the only match — or creates the tag when there is none.
                  onSubmitted: (_) async {
                    if (tags case [final only]) {
                      setState(() => chosen.add(only.id));
                      search.clear();
                    } else if (tags.isEmpty && term.isNotEmpty) {
                      final id = await showNewTagDialog(
                        context,
                        ref,
                        initialName: search.text.trim(),
                      );
                      if (id != null) {
                        setState(() => chosen.add(id));
                        search.clear();
                      }
                    }
                  },
                ),
                const SizedBox(height: HiwiskiMetrics.space8),
                if (tags.isEmpty)
                  Padding(
                    padding: const .symmetric(vertical: HiwiskiMetrics.space8),
                    child: Text(
                      L.of(context).tagSearchNone,
                      style: context.texts.bodyMedium?.copyWith(
                        color: context.scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                for (final tag in tags)
                  Row(
                    children: [
                      Checkbox(
                        value: chosen.contains(tag.id),
                        onChanged: (_) => setState(
                          () => chosen.contains(tag.id)
                              ? chosen.remove(tag.id)
                              : chosen.add(tag.id),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TagChip(tag: tag),
                        ),
                      ),
                      if (tag.ownerId == me) ...[
                        IconButton(
                          icon: const Icon(
                            HiwiskiSymbols.edit,
                            size: HiwiskiMetrics.icon20,
                          ),
                          tooltip: L.of(context).tagEdit,
                          onPressed: () =>
                              showNewTagDialog(context, ref, editing: tag),
                        ),
                        IconButton(
                          icon: const Icon(
                            HiwiskiSymbols.delete,
                            size: HiwiskiMetrics.icon20,
                          ),
                          tooltip: L.of(context).actionDelete,
                          onPressed: () => ref
                              .read(tagsViewModelProvider.notifier)
                              .deleteTag(tag),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: HiwiskiMetrics.space8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AddTagChip(
                    onTap: () async {
                      final id = await showNewTagDialog(
                        context,
                        ref,
                        initialName: tags.isEmpty ? search.text.trim() : '',
                      );
                      if (id != null) setState(() => chosen.add(id));
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(L.of(context).actionCancel),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(chosen),
        child: Text(L.of(context).actionDone),
      ),
    ],
  );
  // Putting a tag on an item counts as using it — the filter bar ranks by that.
  if (result != null) {
    container
        .read(tagsViewModelProvider.notifier)
        .used(result.difference(current));
  }
  return result;
}
