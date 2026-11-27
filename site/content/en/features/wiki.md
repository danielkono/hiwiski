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

A page of the kind *Pinboard* has, below its text, a surface for notes, pictures, lists, calendar weeks and drawings. More on the [pinboard]({{< relref "features/pinboard" >}}) page.

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
