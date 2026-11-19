import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/hiwiski_sheet.dart';
import '../../../domain/catalog/catalog_product.dart';
import 'todo_keys.dart';

// The shopping list's categories: their names, the picker in a shopping
// item's info bar and "Edit categories".

/// A category in the app's language: a built-in one translated, one of the family's
/// own as written. `null` — and a key this app does not know yet — is "Other".
String aisleLabel(L l, CatalogAisle? aisle) {
  if (aisle == null) return l.aisleOther;
  if (aisle.name case final name?) return name;
  return switch (aisle.key) {
    AisleKeys.produce => l.aisleProduce,
    AisleKeys.bakery => l.aisleBakery,
    AisleKeys.meatSeafood => l.aisleMeatSeafood,
    AisleKeys.deli => l.aisleDeli,
    AisleKeys.dairyEggs => l.aisleDairyEggs,
    AisleKeys.breakfast => l.aisleBreakfast,
    AisleKeys.pantry => l.aislePantry,
    AisleKeys.spicesCondiments => l.aisleSpicesCondiments,
    AisleKeys.snacksSweets => l.aisleSnacksSweets,
    AisleKeys.beverages => l.aisleBeverages,
    AisleKeys.frozen => l.aisleFrozen,
    AisleKeys.baby => l.aisleBaby,
    AisleKeys.personalCare => l.aislePersonalCare,
    AisleKeys.household => l.aisleHousehold,
    AisleKeys.pet => l.aislePet,
    _ => l.aisleOther,
  };
}

/// Whether [name] is what a built-in category is called here — the server does not
/// know the labels, so it let "Backwaren" through next to the built-in one, and the
/// picker showed two that could not be told apart. Says so when it is.
bool builtInNameTaken(
  BuildContext context,
  String name,
  List<CatalogAisle> aisles,
) {
  final l = L.of(context);
  final wanted = name.trim().toLowerCase();
  final taken = aisles.any(
    (aisle) => aisle.builtIn && aisleLabel(l, aisle).toLowerCase() == wanted,
  );
  if (taken) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.errorCatalogAisleNameTaken)));
  }
  return taken;
}

/// Runs a catalog change and says what went wrong. Offline it says that categories
/// need a connection (F) rather than "no network".
Future<bool> runCatalogChange(
  BuildContext context,
  AsyncCallback change,
) async {
  try {
    await change();
    return true;
  } on HiwiskiFailure catch (failure) {
    if (context.mounted) {
      final l = L.of(context);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              failure.isNetwork
                  ? l.aisleOffline
                  : failureText(context, failure),
            ),
          ),
        );
    }
    return false;
  }
}

/// A name for a category — new or renamed. `null` if cancelled or left empty.
Future<String?> showAisleNameSheet(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final l = L.of(context);
  final controller = TextEditingController(text: initial);
  final name = await showHiwiskiSheet<String>(
    context: context,
    title: title,
    owns: [controller],
    builder: (context) => TextField(
      key: TodoKeys.aisleName,
      controller: controller,
      autofocus: true,
      textCapitalization: .sentences,
      decoration: InputDecoration(labelText: l.aisleNameLabel),
      onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
    ),
    actions: (context) => [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l.actionCancel),
      ),
      FilledButton(
        key: TodoKeys.aisleNameSave,
        onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        child: Text(l.actionSave),
      ),
    ],
  );
  return name == null || name.isEmpty ? null : name;
}

/// The menu behind **Category** in a shopping item's info bar: the visible categories,
/// "Other" and "New category…". Picking one writes it into the catalog for every row
/// with this product.
Future<void> pickAisle(
  BuildContext context, {
  required Offset at,
  required String productName,
  required CatalogAisle? current,
  required List<CatalogAisle> aisles,
  required Future<CatalogAisle> Function(String name) createAisle,
  required Future<void> Function(String productName, String? aisleId)
  assignAisle,
}) async {
  final l = L.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final offered = offeredAisles(aisles);

  final picked = await showMenu<_AisleChoice>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      for (final aisle in offered)
        _AisleMenuItem(
          _AisleChoice(_AisleChoiceKind.aisle, aisle),
          aisleLabel(l, aisle),
          current: current,
        ),
      _AisleMenuItem(
        const _AisleChoice(_AisleChoiceKind.aisle, null),
        l.aisleOther,
        current: current,
      ),
      const PopupMenuDivider(),
      _AisleMenuItem(
        const _AisleChoice(_AisleChoiceKind.create, null),
        l.aisleNew,
        current: current,
      ),
    ],
  );
  if (picked == null || !context.mounted) return;

  CatalogAisle? target = picked.aisle;
  if (picked.kind == .create) {
    final name = await showAisleNameSheet(context, title: l.aisleNewTitle);
    if (name == null || !context.mounted) return;
    if (builtInNameTaken(context, name, aisles)) return;
    CatalogAisle? created;
    final ok = await runCatalogChange(context, () async {
      created = await createAisle(name);
    });
    if (!ok || !context.mounted) return;
    target = created;
  } else if (target?.id == current?.id) {
    return;
  }
  await runCatalogChange(context, () => assignAisle(productName, target?.id));
}

enum _AisleChoiceKind { aisle, create }

class const _AisleChoice(
  final _AisleChoiceKind kind,

  /// For [_AisleChoiceKind.aisle]: the category, or `null` for "Other".
  final CatalogAisle? aisle,
);

/// One entry of the category menu, ticked when it is the [current] one.
class _AisleMenuItem extends PopupMenuItem<_AisleChoice> {
  _AisleMenuItem(
    _AisleChoice choice,
    String label, {
    required CatalogAisle? current,
  }) : super(
         key: TodoKeys.aisleOption(choice.aisle?.id ?? choice.kind.name),
         value: choice,
         child: Row(
           children: [
             Expanded(child: Text(label)),
             if (choice.kind == .aisle && choice.aisle?.id == current?.id)
               const Icon(HiwiskiSymbols.check, size: HiwiskiMetrics.icon18),
           ],
         ),
       );
}
