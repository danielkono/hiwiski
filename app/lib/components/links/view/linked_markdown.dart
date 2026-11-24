import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/common/app_names.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../domain/common/match_groups.dart';
import '../../../domain/links/link_index.dart';
import '../../../domain/links/link_text.dart';
import '../../../domain/wiki/markdown_editing.dart';
import '../../../domain/wiki/markdown_limits.dart';
import '../../rich_text/view/image_stack.dart';
import '../links_view_model.dart';
import 'link_chip.dart';
import 'task_list_syntax.dart';
import '../../../core/ui/tap_target.dart';
import '../../../core/l10n/generated/app_localizations.dart';

/// Markdown with link chips — the wiki page.
///
/// The link is recognized **before** Markdown's own link rule: custom inline rules are
/// evaluated first, which is why `[Title](hiwiski://…)` never becomes an ordinary link
/// pointing into nowhere.
class LinkedMarkdown extends ConsumerWidget {
  const LinkedMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.selectable = true,
    this.fitContent = true,
    this.onOpen,
    this.onToggleTask,
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;

  /// Whether each paragraph is only as wide as its text, standing at the start. A
  /// text placed in the middle or at the end needs `false`: its paragraphs then
  /// span the whole width and their lines stand where [styleSheet] places them.
  final bool fitContent;
  final ValueChanged<LinkItem>? onOpen;

  /// Ticks the n-th checkbox of the text — a packing list is worked through on the
  /// rendered page. `null`: the boxes are shown, not tappable.
  final ValueChanged<int>? onToggleTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!renderableAsMarkdown(data)) {
      // A block the markdown package would take seconds to minutes to parse, on
      // every render: shown as it was written.
      final plain = Text(
        data,
        style: styleSheet?.p ?? Theme.of(context).textTheme.bodyMedium,
        textAlign: switch (styleSheet?.textAlign) {
          .center => TextAlign.center,
          .end => TextAlign.end,
          _ => TextAlign.start,
        },
      );
      return selectable ? SelectionArea(child: plain) : plain;
    }
    final index = ref.watch(linksViewModelProvider);
    // The builder only gets the state, not which box it is. It is called once per box,
    // in document order, per pass — the count wraps around for a second pass.
    final order = onToggleTask == null ? const <int>[] : taskRenderOrder(data);
    final total = order.length;
    int next = 0;
    final body = MarkdownBody(
      // The Markdown widget only parses again when `data` or the style sheet change —
      // not when the builders do. Without the key, a page rendered before the index
      // has loaded (a reload in the browser) would keep its links as plain text.
      //
      // Keyed by what this text's links show, not by the whole index: any change to
      // any linked item parsed the page again and cleared a selection in progress.
      key: ValueKey(_shownTargets(index, data)),
      data: data,
      fitContent: fitContent,
      styleSheet: total == 0 ? styleSheet : _withTaskColumn(context),
      checkboxBuilder: onToggleTask == null || total == 0
          ? null
          : (checked) {
              final position = order[next++ % total];
              // A box to tick off a packing list with a finger: the tap area is
              // a full target, and a screen reader hears a checkbox.
              return TapTarget(
                onTap: () => onToggleTask?.call(position),
                child: Semantics(
                  checked: checked,
                  label: L.of(context).wikiTaskToggle,
                  child: InkWell(
                    onTap: () => onToggleTask?.call(position),
                    child: Padding(
                      padding: const .only(right: HiwiskiMetrics.space6),
                      child: Icon(
                        checked
                            ? HiwiskiSymbols.checkBox
                            : HiwiskiSymbols.checkBoxOutlineBlank,
                        size: HiwiskiMetrics.icon20,
                        fill: checked ? 1 : 0,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
      extensionSet: taskListExtensions,
      inlineSyntaxes: [_ReferenceSyntax()],
      builders: {
        _referenceTag: _ReferenceBuilder(index: index, onOpen: onOpen),
        _linkTag: _AddressBuilder(image: false),
        _imageTag: _AddressBuilder(image: true),
      },
    );
    // One selection over the whole text, not one per paragraph: a screen reader
    // announced every paragraph of `selectable` Markdown as something to long-press,
    // and a selection could not run from one paragraph into the next.
    return selectable ? SelectionArea(child: body) : body;
  }

  /// The column the list markers stand in, as wide as a tap target: a task box sits
  /// there, and 28 px were too narrow to hit.
  MarkdownStyleSheet _withTaskColumn(BuildContext context) {
    final merged = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .merge(styleSheet);
    final padding = merged.listBulletPadding?.horizontal ?? 0;
    return merged.copyWith(listIndent: HiwiskiMetrics.minTapTarget - padding);
  }

  /// What the chips of [data] show — changing exactly when one of them would.
  static int _shownTargets(LinkIndex index, String data) => Object.hashAll([
    for (final reference in parseReferences(data))
      switch (index.resolve(reference)) {
        final item? => (
          item.itemType,
          item.itemId,
          item.title,
          item.entityKey,
          item.archived,
        ),
        null => null,
      },
  ]);
}

class _ReferenceBuilder extends MarkdownElementBuilder {
  _ReferenceBuilder({required this.index, this.onOpen});

  final LinkIndex index;
  final ValueChanged<LinkItem>? onOpen;

  @override
  // The markdown package's builder API: it asks for a widget.
  // ignore: many_lints/avoid_returning_widgets
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final reference = referenceFromNormalized(
      element.attributes[_refAttribute] ?? '',
    );
    if (reference == null) return null;
    final target = index.resolve(reference);

    // A `Text` and not a custom widget: the Markdown builder pulls the spans out of it
    // and inserts them into the running paragraph. A widget would instead stand next
    // to it as a block of its own, and the sentence would break before it.
    if (target == null) {
      final part = ReferencePart(
        reference,
        raw: element.attributes[_rawAttribute] ?? '',
        label: element.attributes[_labelAttribute],
      );
      return Text(part.fallback, style: parentStyle);
    }
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: .middle,
            child: LinkChip(target: target, onOpen: onOpen),
          ),
        ],
      ),
    );
  }
}

/// A link to somewhere else — `[label](https://…)`, a bare address, or an image from
/// another server — and the family's own images.
///
/// **Images from other servers are not fetched.** The default builder loaded every
/// `![](https://…)` as soon as someone opened the text, and the other server learned
/// who read it and when — a read receipt and a tracker, also from an imported recipe
/// or a subscribed school calendar, which no member wrote. On native it even read
/// `file:` paths. Such an image reads as a link to it instead: the reader decides
/// whether to look at it, in the browser. The family's own images come from the
/// media store, as they do on lines of their own.
///
/// A `Text` with the link inside, and not the link alone: the Markdown builder pulls
/// the spans out of a `Text` into the running paragraph, where any other widget would
/// stand as a block of its own and break the sentence before it.
class _AddressBuilder extends MarkdownElementBuilder {
  _AddressBuilder({required this.image});

  final bool image;

  @override
  // The markdown package's builder API: it asks for a widget.
  // ignore: many_lints/avoid_returning_widgets
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final address =
        element.attributes[image ? _srcAttribute : _hrefAttribute] ?? '';
    final uri = Uri.tryParse(address);
    if (image &&
        uri != null &&
        uri.scheme == UriSchemes.hiwiskiImage &&
        uri.path.isNotEmpty) {
      return ImageStack(imageIds: [uri.path]);
    }
    final written = image
        ? element.attributes[_altAttribute] ?? ''
        : element.textContent;
    final label = written.trim().isEmpty ? address : written.trim();
    // Only what a browser or the mail app opens: `javascript:` or `file:` from an
    // imported text is shown as its label and leads nowhere.
    if (uri == null || !_openableSchemes.contains(uri.scheme.toLowerCase())) {
      return Text(label, style: parentStyle);
    }
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: .baseline,
            baseline: .alphabetic,
            child: _WebLink(
              uri: uri,
              address: address,
              label: label,
              style: parentStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// A link out of the app, in a text.
///
/// **The address shows before it is followed** — while the pointer rests on the label,
/// or on a long press on a phone —, since the label of a link can say anything. A tap
/// opens it in the browser (or the mail app), never inside the app.
class _WebLink extends StatelessWidget {
  const _WebLink({
    required this.uri,
    required this.address,
    required this.label,
    this.style,
  });

  final Uri uri;

  /// The address as it was written — what the reader is shown.
  final String address;
  final String label;

  /// The style of the text around it; the link takes its size and the link colour.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = context.scheme.primary;
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: color,
      decoration: .underline,
      decorationColor: color,
    );
    return Tooltip(
      message: address,
      child: Semantics(
        link: true,
        linkUrl: uri,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              // A device with nothing to open the address with stays where it
              // is. The reader has seen the address and can copy it.
              launchUrl(uri, mode: .externalApplication).ignore();
            },
            child: Text(label, style: linkStyle),
          ),
        ),
      ),
    );
  }
}

/// The schemes a link in a text may open.
const _openableSchemes = {UriSchemes.http, UriSchemes.https, UriSchemes.mailto};

/// The same three alternatives as when parsing — there is only one pattern.
///
/// Matched through a [LinkScanner], not the pattern alone: the parser tries every
/// position, and a line of `[` would cost O(n²) on every render.
class _ReferenceSyntax extends md.InlineSyntax {
  _ReferenceSyntax() : super(linkPattern.pattern);

  final _scanner = LinkScanner();

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final match = _scanner.matchAt(parser.source, startMatchPos ?? parser.pos);
    if (match == null) return false;
    parser.writeText();
    if (onMatch(parser, match)) parser.consume(match.groupOf(0).length);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final reference = referenceIn(match);
    if (reference == null) return false;
    parser.addNode(
      md.Element.empty(_referenceTag)
        ..attributes[_refAttribute] = reference.normalized
        // In case the target is not here: the text as it stood.
        ..attributes[_rawAttribute] = match.groupOf(0)
        ..attributes[_labelAttribute] = labelIn(match) ?? '',
    );
    return true;
  }
}

const String _referenceTag = 'hiwiskiRef';

/// The elements the markdown package makes of a link and of an image.
const _linkTag = 'a';

const _imageTag = 'img';

const _hrefAttribute = 'href';

const _srcAttribute = 'src';

const _altAttribute = 'alt';

const _rawAttribute = 'raw';

const _labelAttribute = 'label';

const _refAttribute = 'ref';
