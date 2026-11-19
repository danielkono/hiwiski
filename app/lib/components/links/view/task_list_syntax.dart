import 'package:markdown/markdown.dart' as md;

/// The markdown package's block syntaxes for lists, with the task box of an item in a
/// **loose** list (a blank line between items, or before a nested list) moved to where
/// the renderer looks for it.
///
/// The package puts the box into the item's first paragraph there, and the renderer only
/// recognises a box that is the item's first child: such a list showed a bullet, and
/// the box itself drew nothing — the first level of a list with a blank line in it had
/// no boxes.
const _paragraph = 'p';
const _input = 'input';

final taskListExtensions = md.ExtensionSet([
  const md.FencedCodeBlockSyntax(),
  const md.TableSyntax(),
  const _TaskUnorderedList(),
  const _TaskOrderedList(),
  const md.FootnoteDefSyntax(),
], md.ExtensionSet.gitHubFlavored.inlineSyntaxes);

class _TaskUnorderedList extends md.UnorderedListWithCheckboxSyntax {
  const _TaskUnorderedList();

  @override
  md.Node parse(md.BlockParser parser) => _hoistBoxes(super.parse(parser));
}

class _TaskOrderedList extends md.OrderedListWithCheckboxSyntax {
  const _TaskOrderedList();

  @override
  md.Node parse(md.BlockParser parser) => _hoistBoxes(super.parse(parser));
}

md.Node _hoistBoxes(md.Node list) {
  if (list is! md.Element) return list;
  for (final item in list.children ?? const <md.Node>[]) {
    if (item is! md.Element) continue;
    final children = item.children;
    if (children == null || children.isEmpty) continue;
    final first = children.first;
    if (first is! md.Element || first.tag != _paragraph) continue;
    final inner = first.children;
    if (inner == null || inner.isEmpty) continue;
    final box = inner.first;
    if (box is md.Element && box.tag == _input) {
      inner.removeAt(0);
      children.insert(0, box);
    }
  }
  return list;
}
