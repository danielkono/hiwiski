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
| `hugo.toml` | configuration: languages, menus, parameters (`version`, `candidate`, `indexable`, the demo's address, the apps' and the preview's links) |
| `content/de/`, `content/en/` | the pages, one tree per language |
| `data/roadmap.toml` | the roadmap's entries, in both languages ("What's new", below) |
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

## The apps page

`/apps` (`content/*/apps.md`, `layouts/apps.html`) says where each app comes from, and
the home page's first box links to it. The page's texts — the steps of each platform,
their buttons — are in its front matter; the links are in `hugo.toml`:

| `params.apps.<platform>` | What |
| --- | --- |
| `store` | the app's page in its store, once it is there |
| `test` | the public test: TestFlight's public link, Google Play's opt-in page |
| `group` | Android only: the Google Group a closed test admits; empty once the test is open |

Whichever is set decides what the card shows: `store` the store's button (and the test
as a second one), only `test` the steps to install the test version, neither "soon". A
step that names a link (`link: group`) disappears while that link is empty, so moving
from the closed to the open test, and from the test to the stores, changes `hugo.toml`
and no template. `params.feedback` is the address testers write to; TestFlight and
Google Play's test name the same one.

The QR code beside the cards opens the page on a phone. Hugo draws it at build time
(`images.QR`), so the page loads nothing from elsewhere; it is hidden on narrow screens,
where the links can be tapped.

## What's new

"What's new" is a section of three pages with a sidebar, like the features:

| Page | What | Layout |
| --- | --- | --- |
| `whats-new/_index.md` | the released versions of `CHANGELOG.md`, each with its anchor (`#2026.1.0`) | `changelog.html` |
| `whats-new/preview.md` | the release candidates: the ways to try them, going back, and their notes | `preview.html` |
| `whats-new/roadmap.md` | what is planned, from `data/roadmap.toml` | `roadmap.html` |

Both lists of versions come from `_partials/release-notes.html`, which splits
`CHANGELOG.md` at its version headings: `## <version> — <date>` is released,
`## <version> — Release candidate` a candidate, `## Unreleased` is not shown.

- Format after *Keep a Changelog*: `## Unreleased` with `### Added`, `### Changed`,
  `### Fixed` and `### Upgrade notes` (what an administrator must do or know: a new
  `.env` variable, a change to the compose file, a minimum app version, a rollback that
  is not possible).
- **Every `feat/…` and `fix/…` branch adds its entry** under `## Unreleased`, written for
  a family's administrator, not as a commit subject — on a release branch in the
  candidate's section instead. CI on `main` and on `release/…` fails a merge of such a
  branch that does not touch the file. `chore/…`, `refactor/…`, `ci/…` add none.
- **No raw HTML.** The build stops if the rendered `CHANGELOG.md` or `LICENSE.md`
  contains a tag Markdown does not write itself (`_partials/no-raw-html.html`).
- At the start of a release branch `tool/changelog.sh candidate` turns `## Unreleased`
  into the candidate's section; at the release `tool/changelog.sh release` gives it its
  date ([`../releasing.md`](../releasing.md)). The anchor stays the version, so a link
  to it keeps working from the preview to the released list.

### A candidate's website

The website describes the released version: the stores, the setup files and the
setup pages are the released version's until the release. At a candidate tag the
release workflow therefore builds the site from the **latest release tag** and takes
only `CHANGELOG.md` and `data/roadmap.toml` from the candidate (`release.yml`, job
`site-build`, step *The released version's pages*). The preview page then shows the
candidate's notes and the roadmap is current, while feature pages, setup pages and
scenes stay the released version's. `params.version` is the release there,
`params.candidate` the candidate (`HUGO_PARAMS_CANDIDATE`).

- A release from before the candidates has no `data/roadmap.toml` and no page for a
  candidate; the site of a candidate after it is the candidate's own.
- While two candidates run at once — a patch beside the next minor version — the site
  shows the changelog of the one tagged last.
- A change to the pages themselves, the roadmap's layout included, reaches the
  website with the next release.

### The preview page

Like the apps page, the texts are the page's (front matter `try`: one card per way to
try the candidate) and the links are `params.preview` in `hugo.toml`:

| Parameter | What |
| --- | --- |
| `demo` | the release candidate's demo, `https://preview.hiwiski.app/` |
| `ios` | TestFlight's public link of the group that gets the candidates |
| `android` | the Google Group that Google Play's track for the candidates admits; its members opt in on the released version's test page (`apps.android.test`) |

Each button of a card names its link by its path in the parameters (`preview.ios`,
`apps.android.test`); `release` is the candidate's pre-release on GitHub. A card whose
links are not all set says it is not set up yet, rather than show half its steps. The
server's card names the image to set, `HIWISKI_VERSION=<candidate>`. While the
changelog holds no candidate, the page says so and shows no ways to try one.

Below the cards: going back. The apps cannot be set back to an older version — the
app is deleted and installed again, after its data is synced — while the server goes
back as after any update.

### The roadmap

`data/roadmap.toml` holds one `[[items]]` block per feature, in the order the page lists
them: `priority` (`now`, `next`, `later` — the group), optionally `status` (`preview`,
`in-progress`, `planned` — a chip), and `de` and `en` with a `title` and optionally a
`text` in Markdown. An unknown priority or status, or a missing title, stops the build.
Without entries the page says the roadmap is coming. A change goes public with the next
candidate or release.

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
