---
title: Wiki & recipes
description: 'A family wiki in Markdown: the Wi-Fi password, the paediatrician, how-tos and grandma''s recipes, linked to tasks and shopping lists.'
weight: 30
scene: wiki-page
lead: Nested pages in Markdown, recipes and links.
---

## Pages in a tree

Nested as deep as you like, rearranged by dragging. You write a page as it will read — headings, lists, checkboxes and images look as they do on the page — or as its Markdown, one tap away in the toolbar. Several images in a row are shown as a stack you can swipe through.

{{< scene name="wiki-page" live=true height=560 >}}Dad's instructions for restarting the router.{{< /scene >}}

## Links

Type `#` and a number or a title to link another page, a task, a list or an event. The link shows as a chip with a preview.

## Recipes

The servings are set with −/+, and the ingredient amounts adjust. The preparation sits below, with images.

{{< scene name="recipe" live=true height=600 >}}Cheese spätzle from grandma's classics.{{< /scene >}}

## Onto the shopping list

"Add to shopping list" takes the ingredients with their scaled amounts. Pantry staples such as salt or oil are already deselected.

## A recipe from a web page

The server fetches a recipe from an address. Before saving, a review screen marks what it could not read with certainty.

{{< scene name="recipe-import" height=760 >}}The review screen of an import.{{< /scene >}}

## Pinboards

A page of the kind *Pinboard* has a canvas below its text. Open it full screen, move around with your fingers, the trackpad or the mouse wheel, and zoom in and out. **Edit** brings three buttons into the bottom right corner — add, draw, tools — whose choices come out onto a ring you turn to see more; on a phone they take the buttons' place, and the button in the middle goes back. Tap text, a note, a picture, a link or a family member to place it in the middle, or hold it and drag it onto the canvas; text is typed right where it stands. **Connection** offers a line, an arrow, a double arrow, a dashed or a dotted line, in a colour and thickness you choose first: drag from one element to another, or tap one after the other, and go on from there; a connection can carry a label. Elements get a colour — one of the eight, or your own, see-through if you like — a text colour, a shape and a text size — or a size of your own —, a note also the place of its text, top, middle or bottom, left, centre or right, and lines that follow its shape if you like, round in an ellipse, pointed in a diamond, and are brought forward or sent back where they overlap; a connection is as thick as you choose. A lasso or a rectangle selects several elements, to move, colour or delete them together — or to align them, line them up side by side or one below the other, spread them out evenly or give them one width, height or size. What you move or resize snaps to the edges, middles, gaps and sizes of the elements around it, with a thin guide; a new picture, note, link or member is as large as the last of its kind. Under Tools you switch snapping off, or turn on a grid that everything snaps to; on a computer, holding ⌘ or Ctrl while dragging places freely. A snippet of text is just as large as its words, a picture keeps its shape, a link shows its target's title or its content, a calendar week one or more calendars side by side — this week, moving on with the days, or a week of the year, an event opening into its card on hover as in the calendar —, and a note's checklist is ticked off with a tap while you read the pinboard. With the **pen** you draw on the pinboard in a colour and thickness of your choice, freehand or as a rectangle, ellipse, triangle, diamond, line or arrow — a shape can be resized later; the **eraser** takes away every stroke you swipe it over, and one tap hides the drawings. **Undo** takes a change back. The knob above a selected element turns it. Tap twice and drag up or down to zoom with one finger. A search on the canvas marks what it finds and lists it — as it lies on the pinboard, alphabetically or by date. **Save as picture** saves the whole pinboard as a PNG, and a page's export can take its pinboards along as pictures.

Several people can work on the same pinboard at once, offline too. Each element is synced on its own: when two people changed the same element at the same time, the pinboard shows your version beside the one everyone sees, and you decide for that element alone.

## History

Every save creates a version. Every version can be looked at and restored.

## How to

{{< steps id="link-pages" title="Create pages and link them" >}}
1. In the page tree tap **+** where the page should go and enter a title.
2. Tap **Edit**. The text becomes editable as it reads, with the toolbar above it; its first button switches to the Markdown source and back.
3. Type `#` and the start of a title or a number such as `WIKI-3`. Pick a suggestion to set the link.
4. Save. Pages are saved when you tap save and when you leave, not while you type.

{{< scene name="wiki-edit" live=true height=560 >}}Try it: link the page "Heating".{{< /scene >}}
{{< /steps >}}

{{< steps id="shop-a-recipe" title="Shop a recipe" >}}
1. Open a recipe and set the servings with −/+.
2. Tap **Add to shopping list**.
3. Pick the list and check the ingredients. Deselect what you already have.
4. **Add** — the ingredients are on the list, in their categories.

{{< scene name="recipe" live=true height=600 >}}First the servings …{{< /scene >}}

{{< scene name="shopping-list" live=true height=520 >}}… then onto the list: the ingredients show up here. Both views share their data.{{< /scene >}}
{{< /steps >}}

{{< steps id="import-a-recipe" title="Import a recipe from a web page" >}}
*You need:* a server.

1. In the page tree tap **+** on a recipe collection, then **Import recipe**.
2. Paste the address of the recipe page and tap **Fetch**.
3. Check title, image, servings and ingredients. Lines read with uncertainty are marked and can be corrected.
4. **Check and add**.
{{< /steps >}}

## Good to know

- Pages are stored as Markdown, whichever way you write them. Whether texts open formatted or as Markdown is set in **Account → Customize**.
- Recipe import and the history need a server; images work without one.
