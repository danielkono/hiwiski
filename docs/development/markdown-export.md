# Markdown export and import

A list or a wiki page leaves the app as Markdown and comes back the same way. The
files are meant to be read and edited by a person in any editor, so the format is
plain Markdown with a YAML front matter — and the import reads far more than the
export writes.

Everything happens on the device (`app/lib/domain/transfer/`, the components
`export` and `import`). The server has no part in it: an export reads the local
database, an import creates items through `LocalWrites` like anything typed, and
they sync from there. It works offline, and without a server.

## What is exported

| From | File |
| --- | --- |
| a task list, a shopping list, a board | one `.md` file |
| a wiki page without subpages and images | one `.md` file |
| a wiki page with subpages or images | a `.zip` archive |

The archive is a folder of notes:

```
Recipes.md
Recipes/Pancakes.md        a subpage lies in the folder named after its parent
Recipes/Pancakes/Tips.md
media/<id>.jpg             every image once
```

Not exported: ids, owners, sharing, assignees, comments, the history, a recurring
task's ticked-off dates, and archived subpages. An import therefore always creates
**new** items owned by whoever imports; it never updates an existing one.

## The front matter

The field names are the database's column names, which a backup uses as well
(`color_token`, `due_date`), so there is one vocabulary for an item written down.
`type` is the table.

```markdown
---
type: wiki_page
title: Pancakes
kind: RECIPE
position: 2048
tags:
  - Breakfast
properties:
  servings: 4
  imageId: "../media/0190….jpg"
  ingredients:
    - {"label": "Flour", "amount": 250, "unit": "g"}
---

The text, as the page stores it.
```

- `tags` are **names**. On import a tag the member has under that name is used, a
  missing one is created.
- `properties` is what the page's kind adds, as stored
  ([`wiki-page-kinds.md`](wiki-page-kinds.md)) — a kind the format knows nothing
  about still makes the round trip.
- **Images and links are relative paths.** In the app an image is
  `![](hiwiski-image:<id>)` and a link to a page `[Title](hiwiski://wiki_page/<id>)`.
  The export rewrites both, relative to the page's file, for what it contains; the
  import turns a path that leads to a file it was given back into the id of what it
  created. An image left out of the export is removed from the text. A link to
  anything not exported stays as it is.

A list is one file, its tasks a Markdown task list:

```markdown
---
type: todo_list
name: Renovation
kind: KANBAN
color_token: TEAL
columns:
  - {"name": "Open", "colorToken": "BLUE", "done": false}
  - {"name": "Done", "colorToken": "GREEN", "done": true}
---

The list's description.

## Open

- [ ] Tiles
  - due_date: 2026-12-24
  - tags: House, Urgent

  The task's description, indented.

## Done

- [x] Get an offer
```

- What a task has beyond its title stands **right below its line** as
  `- field: value`: `due_date`, `due_time`, `rrule`, `amount`, `unit`, `tags`. The
  first other line starts the description; from there everything is text.
- A board has one `## heading` per column, in order. A card stands where the board
  shows it. On import the **column decides** whether a card is done — moving a line
  below "Done" in an editor is how one ticks it off there.

## What an import accepts

- Markdown files (`.md`, `.markdown`) and zip archives, several at once. Each
  archive is a folder of its own; files picked side by side are one folder.
- **A file without front matter** becomes what the place it is imported at holds: a
  list among the tasks (if it has at least one list item — with or without a box), a
  page in the wiki, named after its file.
- **A folder without a file of its name** — notes zipped by hand — becomes an empty
  page of that name, so its pages keep their place below one another.
- A board without valid columns is a plain list; an unknown color is the default; a
  recurrence rule the server would refuse is dropped, since a refused task would hold
  back the whole list.
- What cannot be read (no archive, not UTF-8, a list without tasks, a text beyond
  the sync limit) is listed in the preview and left out; the rest goes on.

Images are kept on the device (`MediaRepository.keep`) under the id the page already
points to, and uploaded once the page has reached the server — an upload names its
item, and the server does not know a page that still waits in the outbox.
