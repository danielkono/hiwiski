import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiwiski/domain/links/reference_completion.dart';
import 'package:hiwiski/domain/links/link_index.dart';

/// **Typing `#` and a key suggests the item** — number and title.
void main() {
  TextEditingValue typed(String text) => .new(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  const items = [
    LinkItem(
      itemType: 'TODO',
      itemId: 't13',
      title: 'Take out the bins',
      entityKey: 'TD-13',
    ),
    LinkItem(
      itemType: 'TODO',
      itemId: 't14',
      title: 'Call the dentist',
      entityKey: 'TD-14',
    ),
    LinkItem(
      itemType: 'WIKI_PAGE',
      itemId: 'p3',
      title: 'Router',
      entityKey: 'WIKI-3',
    ),
    LinkItem(itemType: 'WIKI_PAGE', itemId: 'p9', title: 'Router passwords'),
  ];

  group('what counts as a query', () {
    test('a # with a key right before the cursor', () {
      final query = referenceQueryAt(typed('See #TD'));
      expect(query?.text, equals('TD'));
      expect(query?.start, equals(4));
    });

    test('not a Markdown heading, not a bare #, not inside a word', () {
      expect(referenceQueryAt(typed('# Heading')), isNull);
      expect(referenceQueryAt(typed('See #')), isNull);
      expect(referenceQueryAt(typed('C#')), isNull);
    });
  });

  test('by number first, the newest first — then by title', () {
    expect(
      completeReference(items, 'td').map((item) => item.entityKey),
      equals(['TD-14', 'TD-13']),
    );
    expect(
      completeReference(items, 'rout').map((item) => item.title),
      equals(['Router', 'Router passwords']),
    );
  });

  test('archived items only by their exact number', () {
    const withArchived = [
      ...items,
      LinkItem(
        itemType: 'TODO',
        itemId: 't15',
        title: 'Pack boxes',
        entityKey: 'TD-15',
        archived: true,
      ),
    ];
    // Typing along offers what is current …
    expect(
      completeReference(withArchived, 'td').map((item) => item.entityKey),
      equals(['TD-14', 'TD-13']),
    );
    expect(completeReference(withArchived, 'pack'), isEmpty);
    // … the number typed in full still means that one.
    expect(
      completeReference(withArchived, 'TD-15').single.itemId,
      equals('t15'),
    );
  });

  test('a choice puts the number in place of what was typed', () {
    final value = typed('Ask about #TD');
    final result = applyReference(value, referenceQueryAt(value)!, items[1]);
    expect(result.text, equals('Ask about #TD-14 '));
    expect(result.selection.baseOffset, equals(result.text.length));
  });

  test('an item without a number yet is inserted by its address', () {
    final value = typed('#Router');
    final result = applyReference(value, referenceQueryAt(value)!, items[3]);
    expect(result.text, equals('[Router passwords](hiwiski://wiki_page/p9) '));
  });
}
