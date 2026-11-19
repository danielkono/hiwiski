import 'package:meta/meta.dart';
import 'package:riverpod/experimental/mutation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/repositories.dart';
import '../../../core/common/command.dart';
import '../../../domain/catalog/catalog_product.dart';

part 'categories_view_model.g.dart';

/// `create`, run by a view: it shows the command running and reacts to how it ended.
final createCategoryMutation = Mutation<CatalogAisle>(
  label: 'categoriesViewModel.create',
);

/// Account → Categories: the family's categories and which products sit in them.
/// Every change needs a connection.
@immutable
class CategoriesState {
  CategoriesState({
    required this.aisles,
    required this._products,
    required this.query,
  }) : _known = {for (final aisle in aisles) aisle.id};

  /// The categories this app knows, in the family's order — keys it does not know
  /// stay out: it could only call them "Other".
  final List<CatalogAisle> aisles;

  /// What the product search narrows to; empty shows everything.
  final String query;

  /// By name.
  final List<CatalogProduct> _products;
  final Set<String> _known;

  /// The products of [aisle] — of "Other" for `null`.
  List<CatalogProduct> productsOf(CatalogAisle? aisle) => [
    for (final product in _products)
      if (aisle == null
          ? !_known.contains(product.aisleId)
          : product.aisleId == aisle.id)
        product,
  ];

  /// The products of [aisle] that match the search.
  List<CatalogProduct> shownOf(CatalogAisle? aisle) {
    final term = query.trim().toLowerCase();
    return [
      for (final product in productsOf(aisle))
        if (term.isEmpty || product.name.toLowerCase().contains(term)) product,
    ];
  }

  bool get searching => query.trim().isNotEmpty;
}

@riverpod
Stream<List<CatalogAisle>> _aisles(Ref ref) =>
    ref.watch(catalogRepositoryProvider).watchAisles();

@riverpod
Stream<List<CatalogProduct>> _products(Ref ref) =>
    ref.watch(catalogRepositoryProvider).watch();

@riverpod
class CategoriesViewModel extends _$CategoriesViewModel {
  String _query = '';

  /// The order while a drag is on its way to the server — the list does not jump back.
  List<CatalogAisle>? _pending;

  @override
  Future<CategoriesState> build() async {
    final aisles = ref.watch(_aislesProvider.future);
    final productList = ref.watch(_productsProvider.future);
    final all = await aisles;
    final products = [...await productList]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return CategoriesState(
      aisles:
          _pending ??
          [
            for (final aisle in all)
              if (aisle.known) aisle,
          ],
      products: products,
      query: _query,
    );
  }

  /// Every category, hidden and unknown ones included — a new name must not repeat
  /// a built-in one.
  List<CatalogAisle> get allAisles =>
      ref.read(_aislesProvider).value ?? const <CatalogAisle>[];

  void search(String query) {
    _query = query;
    ref.invalidateSelf();
  }

  @command
  Future<CatalogAisle> create(String name) =>
      ref.read(catalogRepositoryProvider).createAisle(name.trim());

  Future<void> rename(CatalogAisle aisle, String name) =>
      ref.read(catalogRepositoryProvider).renameAisle(aisle.id, name.trim());

  Future<void> setHidden(CatalogAisle aisle, bool hidden) =>
      ref.read(catalogRepositoryProvider).setAisleHidden(aisle.id, hidden);

  Future<void> delete(CatalogAisle aisle) =>
      ref.read(catalogRepositoryProvider).deleteAisle(aisle.id);

  /// The product with exactly this name goes into this category; `null` is "Other".
  Future<void> assign(String productName, String? aisleId) => ref
      .read(catalogRepositoryProvider)
      .assignAisle(productName.trim(), aisleId);

  /// Moves a category; the new order shows at once and stays while it is sent.
  Future<void> reorder(int from, int to) async {
    final current = state.value;
    if (current == null) return;
    final next = [...current.aisles];
    next.insert(to, next.removeAt(from));
    _pending = next;
    ref.invalidateSelf();
    try {
      await ref.read(catalogRepositoryProvider).reorderAisles([
        for (final aisle in next) aisle.id,
      ]);
    } finally {
      _pending = null;
      if (ref.mounted) ref.invalidateSelf();
    }
  }
}
