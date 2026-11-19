import 'package:meta/meta.dart';

import 'catalog_product.dart';

/// One product of the catalog a family starts with.
@immutable
class const SeedProduct({
  required final String name,

  /// The built-in category it goes under — a key from [AisleKeys].
  required final String aisleKey,
  final String? defaultUnit,
});

const _comment = '#';
const _separator = '\t';

/// Reads the seed as the server keeps it (`catalog/products-<language>.tsv`): one
/// product per line, `name<TAB>category key<TAB>usual unit`, the unit optional,
/// comments after `#`. Without a server the device starts from the same file.
List<SeedProduct> parseCatalogSeed(String tsv) => [
  for (final line in tsv.split('\n'))
    if (line.trim() case final trimmed
        when trimmed.isNotEmpty && !trimmed.startsWith(_comment))
      if (trimmed.split(_separator) case [final name, final key, ...final rest])
        SeedProduct(
          name: name.trim(),
          aisleKey: key.trim(),
          defaultUnit: switch (rest) {
            [final unit, ...] when unit.trim().isNotEmpty => unit.trim(),
            _ => null,
          },
        ),
];
