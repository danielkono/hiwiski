# Adding a kind of wiki page

A kind of page — `PAGE`, `RECIPE`, `RECIPE_FOLDER` and whatever comes next — is a page
with a presentation of its own and, often, fields of its own. Recipes are wiki pages
for this reason: a recipe is a page with servings, ingredients and a picture, and it
gets the tree, links and comments of every page for free. All kinds share one table and one entity type, so the tree, moving, sharing, history,
comments, links, search, the archive and the trash work for a new kind without
anything done. **A kind's fields are properties of the page** — no column, no
migration, no change in sync.

The recipe is the reference for every step below.

## Server

**1. A `WikiKind` bean** in `wiki/internal/`, next to `RecipeKind`:

```java
@Component
class ContactKind implements WikiKind {

    @Override
    public String code() {
        return "CONTACT";
    }

    @Override
    public List<SyncProperty> properties() {
        return List.of(
                SyncProperty.text("phone"),
                SyncProperty.text("address"),
                SyncProperty.uuid("photoId"));
    }

    @Override
    public List<String> imageProperties() {
        return List.of("photoId");
    }
}
```

- `properties()` — each is a field on the wire, synced and conflict-checked on its own.
  Types: `text`, `integer`, `decimal`, `flag`, `uuid`, `json` (a list or object,
  replaced as a whole). **Names are unique across all kinds** — the server refuses to
  start otherwise — and never one of the page's columns (`title`, `content`, …).
- `imageProperties()` — properties that hold an image uploaded for the page: checked
  to be the page's own, kept by the weekly cleanup.
- `keyType()` — only for a range of numbers of its own (`REC-12`). Without it the kind
  counts as a page (`WIKI-3`). A range of its own needs an entry in `KeyedEntityType`,
  its setting key in `SettingKey`, the counter row in a migration and the prefix in the
  settings (`api/components/admin.yaml`, `AdminController`, the settings screen) — as
  `TODO_LIST` did in V030.

**2. A test** in `wiki/WikiKindIT` style: the fields arrive, two devices changing
different fields both get through, a value that does not fit is refused.

That is all on the server.

## App

**1. Typed accessors** in `lib/domain/wiki/<kind>_fields.dart`, exported from
`wiki_page.dart` — as `recipe_fields.dart`:

```dart
extension ContactFields on WikiPage {
  String? get phone => property(_phone) as String?;
}

Map<String, Object?> contactChanges({Change<String?>? phone}) => {
  if (phone != null) _phone: phone.value,
};
```

The wire names go into `WireFields` (`lib/core/common/wire.dart`), and into
`historyFieldLabel` (`lib/core/ui/history_field_label.dart`) so history and conflicts
name the field in words.

**2. The presentation**, a folder `lib/features/wiki/page/view/<kind>/` with a
`PageKindView` subclass — as `recipe/recipe_kind.dart`:

| Member | What it says |
| --- | --- |
| `code` | the page's `kind` |
| `offeredAs(l, parent)` | the label in "New page" below `parent`, `null` where not offered |
| `icon(parent)`, `treeIcon(node)` | its symbol in "New page" and in the tree |
| `body(…)` | the page while read; empty: it reads as Markdown text |
| `head(…)` | what stands above the text (a collection's recipe cards) |
| `properties(…)` | the info bar's first rows — where the page sits, what the kind adds |
| `dock(…)` | what stays docked below the page ("Add to shopping list") |
| `draft(page)` | a `PageKindDraft`: the fields editing adds above the text, and `save` |

`save` passes the kind's changes as properties —
`viewModel.edit(base, title: …, content: …, properties: contactChanges(…))`.

**3. One line** in `PageKindView.all` (`page_kind.dart`) — the order "New page" offers
the kinds in.

**4. Strings** in `app_en.arb` and `app_de.arb`; new symbols with
`HiwiskiSymbols.<name>` and `python3 tool/generate_symbols.py`.

**5. Tests**: the kind's fields read and written (`test/page_properties_test.dart`),
its view and its editor.

## What a kind does not need

- No migration, on the server or on the device: properties need no column.
- No change in the codec, the outbox or the sync engine: every field that is not a
  column is a property.
- No change for older apps: they show the kind as text and keep its fields untouched.

## What stays per feature

Features *about* a kind decide for themselves whether it concerns them: the recipe
tile on the boards, the "Recipes" group in the archive and search, the recipe import
and "Add to shopping list" are recipe features and look for `PageKinds.recipe`. A new
kind that wants a board tile or an archive group adds it there.
