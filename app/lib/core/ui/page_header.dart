import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../components/account_avatar/view/account_avatar.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/routes.dart';
import '../shell/breakpoints.dart';
import '../theme/hiwiski_metrics.dart';
import '../theme/hiwiski_symbols.dart';
import '../theme/hiwiski_tokens.dart';
import 'embedded_page.dart';
import 'panel_reopen.dart';
import 'tap_target.dart';

/// The header bars of the screens.
///
/// Three forms, one component:
///
/// * **Phone and tablet** — the title block with kicker, title (26/600) and item
///   line; on a top-level area the search icon (phone only) and the avatar on the
///   right, on a subpage the back arrow on the left and "Edit" on the right. **The
///   avatar leads to the account** — on the phone it is the only way there, and
///   without it account, family and sign-out were unreachable below 1024 px.
/// * **Desktop** — the same row with a larger title (30/600) and wider margins. On
///   desktop the search sits in the drawer.
/// * **Inside another screen** — a list open beside the task lists' rows, a page
///   beside the wiki's tree: the item's title (24/600) directly under the area's
///   header, level with the button that puts the panel beside it away.
///
/// **A top-level area and a subpage have the same header**: the same margins, the same
/// line kept for the kicker, the title at the same place and in the same size. The
/// title of a subpage used to stand a line higher than its area's and in another
/// size, and the same page read as another kind of page. Only a subpage has the item
/// line under its title; an area has none, and no room is kept for one.
///
/// **The item line always reads in the same order**: the citable key, the container as
/// a link, the context — "TD-14 · Household · 5 open". The key is not decoration: you
/// need it to write `#TD-14` in another page, and it is found fastest where it always
/// is — first, and the only part set in mono.
/// A step up from an item to what holds it — "Household" for a task, a link in the
/// header's item line.
@immutable
class const HeaderCrumb({
  required final String label,
  required final VoidCallback onTap,
});

/// Between the parts of the item line.
const _lineSeparator = ' · ';

/// Between one container and the one inside it — "Recipes › Cakes".
const _crumbSeparator = ' › ';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.kicker,
    this.entityKey,
    this.crumbs = const [],
    this.detail,
    this.onBack,
    this.trailing = const [],
    @visibleForTesting this.web = kIsWeb,
  });

  final String title;

  /// "Sunday, September 27" above the title of a top-level area.
  final String? kicker;

  /// "TD-1" — the citable key, first in the item line and set in mono.
  final String? entityKey;

  /// The containers above the item, shown after [entityKey] as links — the way from a
  /// task to its list without going back through the screens in between. Sharing the
  /// item line keeps a header as high with a crumb as without.
  final List<HeaderCrumb> crumbs;

  /// "5 open" — the context, last in the item line.
  final String? detail;

  /// Makes the header a subpage's; outside the browser it also shows the back arrow.
  final VoidCallback? onBack;
  final List<Widget> trailing;

  /// In the browser, which goes back on its own: its back button and the system's
  /// gesture. A second arrow on the page would only compete with them.
  final bool web;

  bool get _isSubPage => onBack != null;

  bool get _showsBack => onBack != null && !web;

  @override
  Widget build(BuildContext context) {
    final breakpoint = Breakpoint.of(context);
    if (EmbeddedPage.of(context)) return _EmbeddedHeader(header: this);
    return breakpoint.isWide
        ? _WideHeader(header: this)
        : _NarrowHeader(header: this, compact: breakpoint.isCompact);
  }
}

/// The header on the phone and the tablet.
class _NarrowHeader extends StatelessWidget {
  const _NarrowHeader({required this.header, required this.compact});

  final PageHeader header;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final showsBack = header._showsBack;
    return Padding(
      padding: .fromLTRB(
        // Next to the arrow the header.title moves in; without one it keeps the page margin.
        switch ((showsBack, compact)) {
          (true, _) => HiwiskiMetrics.space8,
          (false, true) => HiwiskiMetrics.space20,
          (false, false) => HiwiskiMetrics.space32,
        },
        HiwiskiMetrics.space6,
        HiwiskiMetrics.space12,
        HiwiskiMetrics.space8,
      ),
      child: ConstrainedBox(
        // An action is a button high, with or without the back arrow beside it.
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.iconButtonSize,
        ),
        child: Row(
          children: [
            if (header.onBack case final onBack? when showsBack)
              _BackButton(onBack: onBack),
            Expanded(
              child: _TitleBlock(
                title: header.title,
                kicker: header.kicker,
                entityKey: header.entityKey,
                crumbs: header.crumbs,
                detail: header.detail,
                titleStyle: context.texts.headlineMedium,
                // The line above the title is kept on every header: the title of a
                // task stands where the title of its area stood. The item line
                // below it is a subpage's — kept free under an area's title it was
                // empty room between the title and the filter.
                reserveKicker: true,
                reserveLine: header._isSubPage,
              ),
            ),
            _Actions(
              lineBelow: header._isSubPage,
              children: [
                // Once per width: from 600 the search is in the navigation rail
                // beside the page, and a second symbol two fingers away from it
                // said the same.
                if (!header._isSubPage && compact)
                  IconButton(
                    icon: const Icon(HiwiskiSymbols.search),
                    tooltip: L.of(context).searchTitle,
                    onPressed: () => const SearchRoute().go(context),
                  ),
                ...header.trailing,
                if (!header._isSubPage)
                  const AccountAvatar(radius: HiwiskiMetrics.avatarMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row: the title block on the left, actions and avatar on the right, level with
/// the title. The bar above it used to hold nothing but the avatar — 76 px of height
/// for one circle.
class _WideHeader extends StatelessWidget {
  const _WideHeader({required this.header});

  final PageHeader header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .fromLTRB(
        HiwiskiMetrics.space32,
        HiwiskiMetrics.space24,
        HiwiskiMetrics.space32,
        HiwiskiMetrics.space16,
      ),
      child: ConstrainedBox(
        // An action is a button high, with or without the back arrow beside it.
        constraints: const BoxConstraints(
          minHeight: HiwiskiMetrics.iconButtonSize,
        ),
        child: Row(
          children: [
            if (header.onBack case final onBack? when header._showsBack)
              Transform.translate(
                offset: const Offset(-10, 0),
                child: _BackButton(onBack: onBack),
              ),
            Expanded(
              child: _TitleBlock(
                title: header.title,
                kicker: header.kicker,
                entityKey: header.entityKey,
                crumbs: header.crumbs,
                detail: header.detail,
                titleStyle: context.texts.headlineLarge,
                // As on the phone: the kicker's line on every header, the item
                // line on a subpage's only.
                reserveKicker: true,
                reserveLine: header._isSubPage,
              ),
            ),
            _Actions(
              lineBelow: header._isSubPage,
              children: [
                ...header.trailing,
                const SizedBox(width: HiwiskiMetrics.space16),
                const AccountAvatar(radius: HiwiskiMetrics.avatarLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The header of a screen shown inside another: no avatar and no back arrow, which
/// the screen around it has, and no line kept free above the title.
///
/// **Its first row is as high as a button and starts at the top edge**, like the row
/// above the panel beside it. The button that puts that panel away stands at the left
/// of that row, and the one that brings it back stands here, left of the title — at
/// the same place on the screen, so the panel is closed and opened again without
/// moving the pointer.
class _EmbeddedHeader extends StatelessWidget {
  const _EmbeddedHeader({required this.header});

  final PageHeader header;

  @override
  Widget build(BuildContext context) {
    final padding = Breakpoint.of(context).pagePadding;
    final reopen = PanelReopen.of(context);
    return Padding(
      padding: .only(
        left: reopen == null ? padding.left : PanelReopen.inset,
        right: padding.right,
        bottom: HiwiskiMetrics.space8,
      ),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          if (reopen != null) ...[
            reopen,
            const SizedBox(width: HiwiskiMetrics.space4),
          ],
          Expanded(
            child: _TitleBlock(
              title: header.title,
              kicker: null,
              entityKey: header.entityKey,
              crumbs: header.crumbs,
              detail: header.detail,
              titleStyle: context.texts.headlineSmall,
              titleMinHeight: HiwiskiMetrics.iconButtonSize,
              reserveKicker: false,
              reserveLine: true,
            ),
          ),
          for (final action in header.trailing)
            // Level with the title's row, not with title and item line together.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: HiwiskiMetrics.iconButtonSize,
              ),
              child: Center(widthFactor: 1, heightFactor: 1, child: action),
            ),
        ],
      ),
    );
  }
}

/// What stands right of the title: the header's actions and the avatar.
///
/// **Level with kicker and title, with or without an item line below them.** The
/// header's row centers what is in it, and the item line of a subpage makes its title
/// block taller: without the same room under the actions, "Edit" and the avatar stood
/// lower on a task than on the area it was opened from.
class _Actions extends StatelessWidget {
  const _Actions({required this.lineBelow, required this.children});

  final bool lineBelow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final actions = Row(mainAxisSize: .min, children: children);
    if (!lineBelow) return actions;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .end,
      children: [actions, const _ItemLineRoom()],
    );
  }
}

/// As high as the item line, and empty.
class _ItemLineRoom extends StatelessWidget {
  const _ItemLineRoom();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(top: HiwiskiMetrics.space2),
    child: Text('', style: context.tokens.text.monoSmall),
  );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(HiwiskiSymbols.arrowBack),
    onPressed: onBack,
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
  );
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    required this.kicker,
    required this.entityKey,
    required this.crumbs,
    required this.detail,
    required this.titleStyle,
    required this.reserveKicker,
    required this.reserveLine,
    this.titleMinHeight = 0,
  });

  /// The least height of the title's row, the title centered in it — a button's
  /// height where a button stands beside the title.
  final double titleMinHeight;

  final String title;
  final String? kicker;
  final String? entityKey;
  final List<HeaderCrumb> crumbs;
  final String? detail;
  final TextStyle? titleStyle;

  /// Keeps the kicker's line even without one. The top-level areas sit side by side
  /// in the navigation: only the start screen has a date above its title, and without
  /// the empty line every switch to or from it moved the content.
  final bool reserveKicker;

  /// Keeps the item line even without one, for the same reason: a subpage with a key
  /// and one without are equally high.
  final bool reserveLine;

  @override
  Widget build(BuildContext context) {
    final entityKey = this.entityKey ?? '';
    final detail = this.detail ?? '';
    final hasLine =
        entityKey.isNotEmpty || detail.isNotEmpty || crumbs.isNotEmpty;
    final block = Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        if (kicker != null || reserveKicker)
          Text(
            kicker ?? '',
            style: context.texts.bodySmall?.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: titleMinHeight),
          child: Align(
            alignment: .centerLeft,
            heightFactor: 1,
            child: Text(
              title,
              style: titleStyle,
              overflow: .ellipsis,
              maxLines: 2,
            ),
          ),
        ),
        if (hasLine || reserveLine)
          // The line's room. What is in it is laid over this, see below.
          const _ItemLineRoom(),
      ],
    );
    if (!hasLine) return block;
    // The item line lies over the block's lower edge instead of standing in it: a
    // crumb is a link and needs a finger-sized target, and in the column that target
    // made a header with a crumb taller than one without — the content below jumped
    // between a list and its task. Here the target reaches up over the title, which
    // takes no taps, and every header keeps one height.
    return Stack(
      children: [
        block,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ItemLine(
            entityKey: entityKey,
            crumbs: crumbs,
            detail: detail,
          ),
        ),
      ],
    );
  }
}

/// The item line: the key in mono, then the crumbs as links, then the context.
class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.entityKey,
    required this.crumbs,
    required this.detail,
  });

  final String entityKey;
  final List<HeaderCrumb> crumbs;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final mono = context.tokens.text.monoSmall;
    // Only the key is mono: set the same, "5 open" and "12 tags" looked like keys too,
    // and the type said nothing any more.
    final plain = context.texts.bodySmall?.copyWith(
      color: context.scheme.onSurfaceVariant,
      height: mono.height,
      fontSize: mono.fontSize,
    );
    final link = plain?.copyWith(
      color: context.scheme.primary,
      decoration: .underline,
      decorationColor: context.scheme.primary,
    );
    final separator = Text(_lineSeparator, style: plain);
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .end,
      children: [
        if (entityKey.isNotEmpty) Text(entityKey, style: mono),
        for (final (index, crumb) in crumbs.indexed) ...[
          if (index > 0)
            Text(_crumbSeparator, style: plain)
          else if (entityKey.isNotEmpty)
            separator,
          Flexible(
            child: TapTarget(
              onTap: crumb.onTap,
              alignment: .bottomLeft,
              child: Text(
                crumb.label,
                style: link,
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
          ),
        ],
        if (detail.isNotEmpty) ...[
          if (entityKey.isNotEmpty || crumbs.isNotEmpty) separator,
          Flexible(
            child: Text(detail, style: plain, maxLines: 1, overflow: .ellipsis),
          ),
        ],
      ],
    );
  }
}
