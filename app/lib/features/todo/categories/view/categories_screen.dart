import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/row_divider.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/shell/breakpoints.dart';
import '../../../../core/theme/hiwiski_metrics.dart';
import '../../../../core/theme/hiwiski_symbols.dart';
import '../../../../core/theme/hiwiski_tokens.dart';
import '../../../../core/ui/drag_auto_scroll.dart';
import '../../../../core/ui/page_header.dart';
import '../../../../core/ui/hiwiski_page.dart';
import '../../../../domain/catalog/catalog_product.dart';
import '../../view/aisle_ui.dart';
import '../../view/todo_keys.dart';
import '../categories_view_model.dart';

/// **Account → Categories**: the shopping list's
/// categories for the whole family, and which product is in which.
///
/// Per category its products as chips — a tap moves one elsewhere, the cross takes it
/// out ("Other") — and a field to add one. Categories are reordered like a shopping
/// row is moved: by touch after a long press anywhere on the card, with the mouse at
/// once by the handle; near the edge the page scrolls along ([DragAutoScroll]);
/// own ones are renamed and deleted, built-in ones hidden. Every change goes to the
/// server at once and needs a connection.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _newName = TextEditingController();
  final _search = TextEditingController();

  /// The categories whose products are open.
  final _open = <String>{};

  /// Whether a category is being moved — then the page scrolls near its edge.
  bool _reordering = false;
  final _autoScroll = DragAutoScroll();

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
  }

  void _searchChanged() =>
      ref.read(categoriesViewModelProvider.notifier).search(_search.text);

  @override
  void dispose() {
    _autoScroll.stop();
    _newName.dispose();
    _search
      ..removeListener(_searchChanged)
      ..dispose();
    super.dispose();
  }

  List<CatalogAisle> get _aisles =>
      ref.read(categoriesViewModelProvider.notifier).allAisles;

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    if (builtInNameTaken(context, name, _aisles)) return;
    final ok = await runCatalogChange(
      context,
      () => createCategoryMutation.run(
        ref,
        (tsx) => tsx.get(categoriesViewModelProvider.notifier).create(name),
      ),
    );
    if (ok) _newName.clear();
  }

  Future<void> _reorder(int from, int to) => runCatalogChange(
    context,
    () => ref.read(categoriesViewModelProvider.notifier).reorder(from, to),
  );

  Future<void> _rename(CatalogAisle aisle) async {
    final l = L.of(context);
    final name = await showAisleNameSheet(
      context,
      title: l.aisleRenameTitle,
      initial: aisle.name ?? '',
    );
    if (name == null || name == aisle.name || !mounted) return;
    if (builtInNameTaken(context, name, _aisles)) return;
    await runCatalogChange(
      context,
      () => ref.read(categoriesViewModelProvider.notifier).rename(aisle, name),
    );
  }

  Future<void> _delete(CatalogAisle aisle, int count) async {
    final l = L.of(context);
    final name = aisleLabel(l, aisle);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.aisleDelete),
        content: Text(
          count == 0
              ? l.aisleDeleteEmpty(name)
              : l.aisleDeleteConfirm(count, name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.actionCancel),
          ),
          FilledButton(
            key: TodoKeys.aisleDeleteConfirm,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runCatalogChange(
      context,
      () => ref.read(categoriesViewModelProvider.notifier).delete(aisle),
    );
  }

  /// Whether it went through — it needs a connection.
  Future<bool> _assign(String productName, CatalogAisle? aisle) =>
      runCatalogChange(
        context,
        () => ref
            .read(categoriesViewModelProvider.notifier)
            .assign(productName, aisle?.id),
      );

  /// The menu behind a product chip: every other category, and "Other".
  Future<void> _move(
    BuildContext chipContext,
    CatalogProduct product,
    List<CatalogAisle> aisles,
  ) async {
    final l = L.of(context);
    final box = chipContext.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height));
    final picked = await showMenu<_Target>(
      context: context,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(enabled: false, child: Text(l.aisleMoveTo)),
        for (final aisle in offeredAisles(aisles))
          if (aisle.id != product.aisleId)
            PopupMenuItem(
              key: TodoKeys.aisleOption(aisle.id),
              value: _Target(aisle),
              child: Text(aisleLabel(l, aisle)),
            ),
        if (product.aisleId != null)
          PopupMenuItem(
            key: TodoKeys.aisleOption(_other),
            value: const _Target(null),
            child: Text(l.aisleOther),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await _assign(product.name, picked.aisle);
  }

  void _toggle(String id) =>
      setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));

  @override
  Widget build(BuildContext context) {
    final header = PageHeader(
      title: L.of(context).aisles,
      onBack: () => const AccountRoute().go(context),
    );
    return ref
        .watch(categoriesViewModelProvider)
        .when(
          skipLoadingOnReload: true,
          loading: () => HiwiskiPage.loading(header: header),
          error: (error, _) => HiwiskiPage.error(header: header, error: error),
          data: (state) {
            final l = L.of(context);
            final padding = Breakpoint.of(context).pagePadding;
            final aisles = state.aisles;

            final other = state.productsOf(null);

            return HiwiskiPage(
              header: header,
              body: ListView(
                padding: padding.add(
                  const .only(bottom: HiwiskiMetrics.space32),
                ),
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: HiwiskiMetrics.listMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          Text(
                            l.aislesHint,
                            style: context.texts.bodyMedium?.copyWith(
                              color: context.scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: HiwiskiMetrics.space16),
                          Row(
                            children: [
                              Expanded(
                                child: _PillField(
                                  key: TodoKeys.categoryNew,
                                  controller: _newName,
                                  hint: l.aisleNewTitle,
                                  onSubmitted: (_) => _create(),
                                ),
                              ),
                              const SizedBox(width: HiwiskiMetrics.space8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(
                                    0,
                                    HiwiskiMetrics.buttonHeight,
                                  ),
                                ),
                                icon: const Icon(
                                  HiwiskiSymbols.add,
                                  size: HiwiskiMetrics.icon20,
                                ),
                                label: Text(l.aisleCreate),
                                onPressed: _create,
                              ),
                            ],
                          ),
                          const SizedBox(height: HiwiskiMetrics.space12),
                          _PillField(
                            key: TodoKeys.categorySearch,
                            controller: _search,
                            hint: l.aisleProductSearch,
                            icon: HiwiskiSymbols.search,
                          ),
                          const SizedBox(height: HiwiskiMetrics.space16),
                          // One card for all categories, parted by lines, as the
                          // tags and the calendars have it — not a card for each.
                          Material(
                            color: context.scheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                color: context.scheme.outlineVariant,
                              ),
                              borderRadius: const .all(
                                .circular(HiwiskiMetrics.radiusCard),
                              ),
                            ),
                            clipBehavior: .antiAlias,
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: [
                                // The list does not scroll itself — the page does, so its own
                                // edge scrolling never starts; the pointer drives it instead.
                                Builder(
                                  builder: (listContext) => Listener(
                                    onPointerMove: (event) {
                                      if (_reordering) {
                                        _autoScroll.update(
                                          listContext,
                                          event.position,
                                        );
                                      }
                                    },
                                    child: ReorderableListView(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      buildDefaultDragHandles: false,
                                      onReorderStart: (_) => _reordering = true,
                                      onReorderEnd: (_) {
                                        _reordering = false;
                                        _autoScroll.stop();
                                      },
                                      onReorderItem: _reorder,
                                      children: [
                                        for (final (index, aisle)
                                            in aisles.indexed)
                                          _CategoryCardFor(
                                            key: TodoKeys.categoryCard(
                                              aisle.id,
                                            ),
                                            owner: this,
                                            state: state,
                                            aisle: aisle,
                                            index: index,
                                            first: index == 0,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (other.isNotEmpty)
                                  _CategoryCardFor(
                                    key: TodoKeys.categoryCard(_other),
                                    owner: this,
                                    state: state,
                                    aisle: null,
                                    first: aisles.isEmpty,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}

const _other = 'other';

class const _Target(
  /// `null` is "Other".
  final CatalogAisle? aisle,
);

/// A rounded field — the same as the input on the tags page.
class _PillField extends StatelessWidget {
  const _PillField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: HiwiskiMetrics.buttonHeight,
    child: TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      textCapitalization: .sentences,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: HiwiskiMetrics.icon20),
        contentPadding: const .symmetric(horizontal: HiwiskiMetrics.space16),
        border: const OutlineInputBorder(
          borderRadius: .all(.circular(HiwiskiMetrics.radiusPill)),
        ),
      ),
    ),
  );
}

/// One category: handle, name, product count, its actions — and, open, its products
/// with a field to add one.
class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.aisle,
    required this.index,
    required this.count,
    required this.open,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onHide,
    required this.products,
    required this.onAdd,
    required this.first,
  });

  /// The first row of the card has no line above it.
  final bool first;

  /// `null` is "Other": not reorderable, nothing to rename.
  final CatalogAisle? aisle;

  /// Its place in the reorderable list, `null` for "Other".
  final int? index;
  final int count;
  final bool open;
  final VoidCallback? onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onHide;
  final List<Widget> products;

  /// Whether the product was added — the field is cleared only then.
  final Future<bool> Function(String name)? onAdd;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  /// Clears the field only once the product is in: the add needs a connection, and
  /// offline the typed name was gone with the "needs a connection" message.
  Future<void> _submit() async {
    final name = _add.text.trim();
    final add = widget.onAdd;
    if (name.isEmpty || add == null) return;
    if (await add(name) && mounted) _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = context.scheme;
    final aisle = widget.aisle;
    final hidden = aisle?.hidden ?? false;
    final muted = scheme.onSurfaceVariant;

    // A row of the categories' one card. A Material of its own, so the row has a
    // ground while it is held and moved out of the card.
    return Material(
      color: context.scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (!widget.first) const RowDivider(),
          // Long press on the head moves the card, as a shopping row; the handle
          // moves it at once with the mouse. Not on the products below: a long
          // press there selects text.
          _MoveByLongPress(
            index: widget.index,
            child: InkWell(
              onTap: widget.onToggle,
              child: Padding(
                padding: const .all(HiwiskiMetrics.space4),
                // The head opens and closes the card: as high as a tap target.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight:
                        HiwiskiMetrics.minTapTarget - 2 * HiwiskiMetrics.space4,
                  ),
                  child: Row(
                    children: [
                      if (widget.index case final index?)
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const .all(HiwiskiMetrics.space8),
                            child: Icon(
                              HiwiskiSymbols.dragIndicator,
                              color: muted,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: HiwiskiMetrics.iconButtonSize),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: aisleLabel(l, aisle)),
                              if (hidden)
                                TextSpan(
                                  text: ' · ${l.aisleHidden}',
                                  style: TextStyle(color: muted),
                                ),
                            ],
                          ),
                          style: context.texts.bodyLarge?.copyWith(
                            fontWeight: .w500,
                            color: hidden ? muted : null,
                          ),
                        ),
                      ),
                      Text(
                        '${widget.count}',
                        style: context.tokens.text.entityKey,
                      ),
                      if ((widget.onHide, aisle) case (
                        final onHide?,
                        final aisle?,
                      ))
                        IconButton(
                          key: TodoKeys.aisleHide(aisle.id),
                          tooltip: hidden ? l.aisleShow : l.aisleHide,
                          onPressed: onHide,
                          icon: Icon(
                            hidden
                                ? HiwiskiSymbols.visibilityOff
                                : HiwiskiSymbols.visibility,
                            color: muted,
                          ),
                        ),
                      if (widget.onRename case final onRename?)
                        IconButton(
                          tooltip: l.aisleRenameTitle,
                          onPressed: onRename,
                          icon: Icon(HiwiskiSymbols.edit, color: muted),
                        ),
                      if ((widget.onDelete, aisle) case (
                        final onDelete?,
                        final aisle?,
                      ))
                        IconButton(
                          key: TodoKeys.aisleDelete(aisle.id),
                          tooltip: l.aisleDelete,
                          onPressed: onDelete,
                          icon: Icon(HiwiskiSymbols.delete, color: muted),
                        ),
                      Icon(
                        widget.open
                            ? HiwiskiSymbols.expandLess
                            : HiwiskiSymbols.expandMore,
                        color: muted,
                      ),
                      const SizedBox(width: HiwiskiMetrics.space8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.open)
            Padding(
              padding: const .only(
                left: HiwiskiMetrics.space16,
                right: HiwiskiMetrics.space16,
                bottom: HiwiskiMetrics.space12,
              ),
              child: Column(
                crossAxisAlignment: .stretch,
                children: [
                  if (widget.products.isEmpty)
                    Text(
                      l.aisleNoProducts,
                      style: context.texts.bodySmall?.copyWith(color: muted),
                    )
                  else
                    Wrap(
                      spacing: HiwiskiMetrics.space6,
                      runSpacing: HiwiskiMetrics.space6,
                      children: widget.products,
                    ),
                  if (widget.onAdd != null) ...[
                    const SizedBox(height: HiwiskiMetrics.space8),
                    TextField(
                      key: TodoKeys.categoryAddProduct(aisle?.id ?? _other),
                      controller: _add,
                      onSubmitted: (_) => _submit(),
                      textCapitalization: .sentences,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l.aisleProductAdd,
                        suffixIcon: IconButton(
                          tooltip: l.aisleProductAdd,
                          onPressed: _submit,
                          icon: const Icon(HiwiskiSymbols.add),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MoveByLongPress extends StatelessWidget {
  const _MoveByLongPress({required this.index, required this.child});

  /// `null` for "Other", which does not move.
  final int? index;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (index) {
    final index? => ReorderableDelayedDragStartListener(
      index: index,
      child: child,
    ),
    null => child,
  };
}

/// One category's card, with what the screen holds for it: open or not, and the
/// actions that ask first.
class _CategoryCardFor extends ConsumerWidget {
  const _CategoryCardFor({
    super.key,
    required this.owner,
    required this.state,
    required this.aisle,
    required this.first,
    this.index,
  });

  final bool first;
  final _CategoriesScreenState owner;
  final CategoriesState state;
  final CatalogAisle? aisle;
  final int? index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final aisle = this.aisle;
    final own = state.productsOf(aisle);
    final shown = state.shownOf(aisle);
    final id = aisle?.id ?? _other;
    // A search opens every category with a hit.
    final open = state.searching ? shown.isNotEmpty : owner._open.contains(id);
    return _CategoryCard(
      aisle: aisle,
      index: index,
      first: first,
      count: own.length,
      open: open,
      onToggle: !state.searching ? () => owner._toggle(id) : null,
      onRename: aisle == null || aisle.builtIn
          ? null
          : () => owner._rename(aisle),
      onDelete: aisle == null || aisle.builtIn
          ? null
          : () => owner._delete(aisle, own.length),
      onHide: aisle != null && aisle.builtIn
          ? () => runCatalogChange(
              context,
              () => owner.ref
                  .read(categoriesViewModelProvider.notifier)
                  .setHidden(aisle, !aisle.hidden),
            )
          : null,
      products: [
        for (final product in shown)
          Builder(
            builder: (chipContext) => InputChip(
              key: TodoKeys.categoryProduct(product.id),
              label: Text(product.name),
              onPressed: () => owner._move(chipContext, product, state.aisles),
              onDeleted: aisle == null
                  ? null
                  : () => owner._assign(product.name, null),
              deleteButtonTooltipMessage: l.aisleRemoveProduct,
            ),
          ),
      ],
      // Adding to "Other" would only create a product without a category.
      onAdd: aisle == null ? null : (name) => owner._assign(name, aisle),
    );
  }
}
