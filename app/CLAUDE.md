# Hiwiski app

The rules and the structure are in `docs/development/app.md` — read its sections
*Layers*, *Analysis* and *Riverpod pitfalls* before writing a screen, a ViewModel or a
repository. This file holds what matters for working with tools.

## Formatting

**`dart format` is the only correct formatting** — with its defaults, no project-specific
style and no hand-formatting that deviates from it. Format every Dart file you touch:

```sh
dart format <changed files>
```

Generated code (`*.g.dart`, `*.freezed.dart`, `lib/core/api/generated/`,
`lib/core/l10n/generated/`) is left as its generator writes it.

## Dart tooling

**Use the Dart MCP server (`mcp__dart__*`) instead of Bash** for anything it covers:
analysis (`analyze_files`), formatting, tests, pub commands, package lookup
(`read_package_uris`, `rip_grep_packages`, `pub_dev_search`) and the running app (`dtd`,
hot reload/restart, runtime errors, widget inspector). Fall back to the CLI
(`dart analyze`, `dart format`, …) only when the MCP server is unavailable or a tool
cannot do the job.

## Analysis

`flutter analyze` does not run analyzer plugins and so misses the project's own rules
(`tool/hiwiski_lints`). Use `dart analyze`. CI runs it with `--fatal-infos`: every
finding fails the build.

The rules most often hit, in short (details in `docs/development/app.md`):

- **`no_string_literals`** — wire codes, keys, routes and SQL go into named constants;
  UI text into `app_en.arb` and `app_de.arb`.
- **`no_magic_dimensions`** — sizes come from `HiwiskiMetrics`.
- **`synced_writes`** — synced rows only through `LocalWrites`; never work around it with
  an `ignore`.
- **`layer_boundaries`**, **`view_model_names`**, **`view_model_commands`**,
  **`async_state`** — the MVVM structure.

## Before you finish

- `dart run build_runner build --delete-conflicting-outputs` after changing a table, a
  ViewModel, a Freezed class or an ARB file.
- `dart analyze` clean, `flutter test` green, `dart format` on the changed files.
- A new package: its license checked, a native library's entered in
  `assets/licenses/native.json` (`docs/development/app.md`, "Licenses").
- A new UI string in both ARB files; a new symbol through `HiwiskiSymbols` and
  `python3 tool/generate_symbols.py`.
- A change to the local schema: a migration step in `hiwiski_database.dart` and its test
  — never recreate the database.
