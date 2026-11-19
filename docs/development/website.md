# The website

`site/` is the public website: what Hiwiski is, its features, the **setup guide for
administrators** (the only one — a change to how an instance is set up changes these
pages, in both languages, in the same branch), the release notes and the license. It
embeds real views of the app, running on sample data ("scenes").

## Building it

```sh
cd site
hugo server                 # http://localhost:1313, live reload
hugo --panicOnWarning       # what CI runs: a warning fails the build
```

A local build has no search (Pagefind runs only in the release) and shows a scene's
poster but cannot start it (the embed build is made by the release, below).

CI checks every branch: `tool/site_translations.sh` (both language trees have the same
pages and keys) and `hugo --panicOnWarning`.

## Layout

| Path | What |
| --- | --- |
| `hugo.toml` | configuration: languages, menus, parameters (`version`, `indexable`, the demo's address) |
| `content/de/`, `content/en/` | the pages, one tree per language |
| `i18n/de.toml`, `i18n/en.toml` | short UI texts: buttons, menus, footer |
| `layouts/` | templates; `_partials/` for header, footer, meta tags, icons; `_shortcodes/` for `scene` and `steps` |
| `assets/` | CSS and the site's small scripts |
| `static/` | files copied as they are |

## Languages

- German and English under `/de/…` and `/en/…` (`defaultContentLanguageInSubdir`).
  `/` picks one by `Accept-Language` in the image's Caddyfile — no cookie, no script.
- **File names are English in both trees**; German addresses come from `slug` in the
  front matter (`content/de/setup/_index.md` → `/de/einrichtung/`). Hugo pairs
  translations by their path.
- Hugo has no fallback: a page missing in one tree does not exist there, which is why CI
  compares the trees.
- German pages and `i18n/de.toml` are German text and stay German; front matter keys,
  file names and comments are English. German addresses the reader with "du".
- The release notes are English on both sites; the German page says so above them.

## Scenes

A scene is one real view of the app on the demo's sample data, under a name
(`shopping-list`, `calendar-week`, …). The catalog is in `app/lib/app/scenes/`, and it
serves twice:

1. **Screenshots.** `app/test/scenes/scene_screenshots_test.dart` renders every scene
   to PNG, light and dark, German and English. They are the scene's poster, the fallback
   without JavaScript, and what search engines see; they cannot go stale. Scenes that
   need a server are rendered signed in against a faked one
   (`app/test/scenes/scene_server.dart`).
2. **Live views.** A web build of its own (`app/lib/app/scenes/main.dart`, built with
   `HIWISKI_DEMO=true`, served under `/embed/`) runs Flutter's multi-view mode: one
   engine per page, every scene a view added with
   `app.addView({hostElement, initialData: {scene, lang}})`, all under one
   `ProviderScope`, so the scenes of a page share their data.

In Markdown:

```
{{< scene name="shopping-list" live=true height=520 >}}Caption{{< /scene >}}
```

It renders the poster and a "Try it" button. **The engine loads on the first click**,
not on page load (several megabytes); further scenes on the page start at once. A scene
that navigates away from where it began shows "Back to the start".

What the embed build must respect:

- **It never touches the page's address**: no path URL strategy, no route reporting;
  each scene's router sets `overridePlatformDefaultLocation`.
- **Nothing lands in browser storage**: preferences use an in-memory store, the database
  is in memory.
- **One canvas per view**: `canvasKitForceMultiSurfaceRasterizer` in
  `app/web/flutter_bootstrap.js`, or the browser cuts every scene to the height of the
  last one added.
- **Fixed heights**: an app screen needs a bounded height; the shortcode sets it.
- The sample data is the demo's (`app/assets/demo/demo-<lang>.json`); the language comes
  from the page (`<html lang>`), not the browser. `demo_seed_test.dart` keeps both
  languages in step.

## Release notes

`CHANGELOG.md` at the root is rendered as the "What's new" page
(`layouts/changelog.html`), each version with its own anchor (`#2026.1.0`).

- Format after *Keep a Changelog*: `## Unreleased` with `### Added`, `### Changed`,
  `### Fixed` and `### Upgrade notes` (what an administrator must do or know: a new
  `.env` variable, a change to the compose file, a minimum app version, a rollback that
  is not possible).
- **Every `feat/…` and `fix/…` branch adds its entry** under `## Unreleased`, written for
  a family's administrator, not as a commit subject. CI on `main` fails a merge of such a
  branch that does not touch the file. `chore/…`, `refactor/…`, `ci/…` add none.
- **No raw HTML.** The build stops if the rendered `CHANGELOG.md` or `LICENSE.md`
  contains a tag Markdown does not write itself (`_partials/no-raw-html.html`).
- At a release `tool/changelog.sh` turns `## Unreleased` into the version
  ([`../releasing.md`](../releasing.md)).

## Search engines and previews

`layouts/_partials/meta.html` writes the title and description (the page's
`description`, else its `lead`, else the start of its text), a canonical link,
`hreflang` for both languages with `x-default`, Open Graph images (the page's scene) and,
on the home page, JSON-LD. `params.indexable` in `hugo.toml` controls `noindex`; the
search page and "not found" are always `noindex`. `robots.txt` keeps crawlers out of
`/embed/` and `/pagefind/`.

## The image

The release builds `ghcr.io/danielkono/hiwiski-site:<version>`
(`deploy/site-image/`): Caddy serving the Hugo output, the Pagefind index, the scene
screenshots and the embed build under `/embed/`, all from one origin. Its Content
Security Policy allows `'wasm-unsafe-eval'` and nothing from elsewhere. The steps are in
`.github/workflows/release.yml` (`site-build`, `site-image`); Hugo and Pagefind come at
pinned versions and checksums from `tool/site_tools.sh`.

The site links to a legal notice and a privacy policy at `/impressum`, `/datenschutz`
and `/privacy`; those are served by whoever hosts the site, not by this image.
