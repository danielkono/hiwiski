package de.danielkononov.hiwiski.wiki.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.LimitedBody;
import de.danielkononov.hiwiski.platform.OutboundUrls;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * Fetches a page and takes apart the {@code schema.org/Recipe} in it.
 *
 * <p><strong>No outbound request into the local network</strong>:
 * the resolved IP is checked against private ranges, loopback, link-local and metadata
 * addresses — before <em>and after</em> every redirect. Otherwise the import becomes a
 * tool for talking to the router.
 *
 * <p>Only {@code application/ld+json} is read. An HTML parser would be one more
 * dependency for pages that ship structured data anyway — and a page that does not ship
 * it does not deliver a reliable recipe either.
 */
@Component
class RecipeImporter {

    private static final Logger log = LoggerFactory.getLogger(RecipeImporter.class);

    /** Enough for a recipe page; beyond that it is not one any more. */
    private static final int MAX_BYTES = 4 * 1024 * 1024;

    private static final int MAX_REDIRECTS = 5;

    /**
     * No recipe has more ingredients; a page that sends more is not delivering a recipe.
     * Together with {@link IngredientParser#MAX_LINE} it bounds the parsing work per import.
     */
    static final int MAX_INGREDIENTS = 200;

    /**
     * The type attribute, looked for <em>inside one opening tag</em> only.
     *
     * <p>The regex used to run over the whole page ({@code <script[^>]+type…(.*?)</script>})
     * and was quadratic in the number of {@code <script} that never closed: a 320 KB page
     * took 24 s, the 4 MiB limit about an hour. The blocks
     * are now found with a linear scan, and only the short tag goes through this pattern.
     */
    private static final Pattern LD_JSON_TYPE = Pattern.compile(
            "\\stype\\s*+=\\s*+[\"']?application/ld\\+json", Pattern.CASE_INSENSITIVE);

    private final IngredientParser ingredients;
    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NEVER)
            .connectTimeout(Duration.ofSeconds(8))
            .build();

    RecipeImporter(IngredientParser ingredients) {
        this.ingredients = ingredients;
    }

    record Ingredient(java.math.BigDecimal amount, String unit, String label, boolean uncertain) {}

    record Recipe(
            String title,
            Integer servings,
            Integer durationMinutes,
            String imageUrl,
            String sourceUrl,
            String content,
            List<Ingredient> ingredients) {}

    Recipe fetch(String url) {
        return parse(get(url), url);
    }

    /** The recipe in a page — apart from fetching it, so it can be tested without a network. */
    Recipe parse(String html, String url) {
        JsonNode recipe = findRecipe(html);
        if (recipe == null) {
            throw HiwiskiException.invalid("recipe.not_found", "url", url);
        }
        return toRecipe(recipe, url);
    }

    /** Redirects by hand, with a check <strong>after each one</strong>. */
    private String get(String url) {
        String current = url;
        for (int hop = 0; hop <= MAX_REDIRECTS; hop++) {
            URI uri = OutboundUrls.require(current);
            HttpResponse<java.io.InputStream> response;
            try {
                response = http.send(
                        HttpRequest.newBuilder(uri)
                                .timeout(Duration.ofSeconds(20))
                                .header("Accept", "text/html,application/xhtml+xml")
                                .GET()
                                .build(),
                        HttpResponse.BodyHandlers.ofInputStream());
            } catch (java.io.IOException e) {
                throw HiwiskiException.invalid("recipe.unreachable", "url", url);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw HiwiskiException.invalid("recipe.unreachable", "url", url);
            }

            int status = response.statusCode();
            if (status != 200) {
                LimitedBody.discard(response);
            }
            if (status >= 300 && status < 400) {
                current = response.headers()
                        .firstValue("location")
                        .map(location -> uri.resolve(location).toString())
                        .orElseThrow(() -> HiwiskiException.invalid("recipe.unreachable", "url", url));
                continue;
            }
            if (status != 200) {
                throw HiwiskiException.invalid("recipe.http_error", "status", status);
            }
            // Read up to the limit, not past it: a URL that streams gigabytes used to be
            // buffered whole before its size was looked at.
            try {
                return LimitedBody.read(response, MAX_BYTES)
                        .orElseThrow(() -> HiwiskiException.invalid("recipe.too_large", "url", url));
            } catch (java.io.IOException e) {
                throw HiwiskiException.invalid("recipe.unreachable", "url", url);
            }
        }
        throw HiwiskiException.invalid("recipe.too_many_redirects", "url", url);
    }

    private JsonNode findRecipe(String html) {
        for (String block : ldJsonBlocks(html)) {
            try {
                JsonNode node = mapper.readTree(block);
                JsonNode found = search(node);
                if (found != null) {
                    return found;
                }
            } catch (RuntimeException e) {
                // A broken block must not cost the others: pages often deliver several,
                // and only one of them is the recipe.
                log.debug("skipping unreadable ld+json block", e);
            }
        }
        return null;
    }

    /**
     * The contents of every {@code <script type="application/ld+json">} block, in order.
     *
     * <p>A single pass: each search starts where the last one ended, so the work is linear
     * in the length of the page however it is built.
     *
     * <p>Only a real {@code <script} tag opens a block: the name has to end there, in
     * whitespace, {@code >} or {@code /}. Comments and {@code <template>} contents are
     * skipped, as a browser does. Before, {@code <scripty>}, {@code <script-x>} or a
     * {@code <script} in a comment ran on to the {@code </script} of the recipe block, and
     * the recipe was not found.
     */
    static List<String> ldJsonBlocks(String html) {
        List<String> blocks = new ArrayList<>();
        int from = 0;
        while (true) {
            int open = html.indexOf('<', from);
            if (open < 0) {
                return blocks;
            }
            if (html.startsWith("<!--", open)) {
                int end = html.indexOf("-->", open + "<!--".length());
                if (end < 0) {
                    return blocks;
                }
                from = end + "-->".length();
                continue;
            }
            if (tagAt(html, open, "<template")) {
                int end = indexOfIgnoreCase(html, "</template", open + "<template".length());
                if (end < 0) {
                    return blocks;
                }
                from = end + "</template".length();
                continue;
            }
            if (!tagAt(html, open, "<script")) {
                from = open + 1;
                continue;
            }
            int tagEnd = html.indexOf('>', open);
            if (tagEnd < 0) {
                return blocks;
            }
            int close = indexOfIgnoreCase(html, "</script", tagEnd + 1);
            if (close < 0) {
                return blocks;
            }
            String tag = html.substring(open + "<script".length(), tagEnd);
            if (LD_JSON_TYPE.matcher(tag).find()) {
                blocks.add(html.substring(tagEnd + 1, close));
            }
            from = close + "</script".length();
        }
    }

    /** Whether the tag {@code name} (with its {@code <}) starts at {@code at}, and ends its name there. */
    private static boolean tagAt(String html, int at, String name) {
        int after = at + name.length();
        if (after >= html.length() || !html.regionMatches(true, at, name, 0, name.length())) {
            return false;
        }
        char next = html.charAt(after);
        return next == '>' || next == '/' || Character.isWhitespace(next);
    }

    private static int indexOfIgnoreCase(String text, String needle, int from) {
        int last = text.length() - needle.length();
        char first = needle.charAt(0);
        for (int i = Math.max(from, 0); i <= last; i++) {
            if (text.charAt(i) == first && text.regionMatches(true, i, needle, 0, needle.length())) {
                return i;
            }
        }
        return -1;
    }

    /** {@code @graph}, arrays and nested nodes -- all three occur. */
    private JsonNode search(JsonNode node) {
        if (node == null) {
            return null;
        }
        if (node.isArray()) {
            for (JsonNode child : node) {
                JsonNode found = search(child);
                if (found != null) {
                    return found;
                }
            }
            return null;
        }
        if (node.isObject()) {
            if (isRecipe(node.get("@type"))) {
                return node;
            }
            JsonNode graph = node.get("@graph");
            return graph == null ? null : search(graph);
        }
        return null;
    }

    private static boolean isRecipe(JsonNode type) {
        if (type == null) {
            return false;
        }
        if (type.isArray()) {
            for (JsonNode value : type) {
                if ("Recipe".equals(value.asString(""))) {
                    return true;
                }
            }
            return false;
        }
        return "Recipe".equals(type.asString(""));
    }

    private Recipe toRecipe(JsonNode node, String sourceUrl) {
        List<Ingredient> parsed = new ArrayList<>();
        JsonNode lines = node.get("recipeIngredient");
        if (lines != null && lines.isArray()) {
            for (JsonNode line : lines) {
                if (parsed.size() == MAX_INGREDIENTS) {
                    break;
                }
                var item = ingredients.parse(line.asString(""));
                parsed.add(new Ingredient(item.amount(), item.unit(), item.label(), item.uncertain()));
            }
        }

        return new Recipe(
                text(node.get("name")),
                servings(node.get("recipeYield")),
                duration(node),
                image(node.get("image")),
                sourceUrl,
                content(text(node.get("description")), instructions(node.get("recipeInstructions"))),
                parsed);
    }

    /**
     * The description, then the steps. Before, only the steps came along, and the few
     * lines a page puts above them — what the dish is, what it goes with — were lost.
     */
    private static String content(String description, String steps) {
        String intro = description == null || description.isBlank() ? null : description.trim();
        if (intro == null) {
            return steps;
        }
        return steps == null ? intro + "\n" : intro + "\n\n" + steps;
    }

    /** {@code totalTime}, or else preparation plus cooking — many pages give only those two. */
    private static Integer duration(JsonNode node) {
        Integer total = minutes(text(node.get("totalTime")));
        if (total != null) {
            return total;
        }
        Integer prep = minutes(text(node.get("prepTime")));
        Integer cook = minutes(text(node.get("cookTime")));
        if (prep == null && cook == null) {
            return null;
        }
        return (prep == null ? 0 : prep) + (cook == null ? 0 : cook);
    }

    private static String text(JsonNode node) {
        return node == null ? null : node.asString(null);
    }

    /** {@code "4"}, {@code "4 Portionen"}, {@code ["4"]} -- all three occur. */
    private static Integer servings(JsonNode node) {
        if (node == null) {
            return null;
        }
        String raw = node.isArray() && !node.isEmpty() ? node.get(0).asString("") : node.asString("");
        Matcher digits = Pattern.compile("\\d+").matcher(raw);
        return digits.find() ? Integer.valueOf(digits.group()) : null;
    }

    /** ISO 8601 duration: {@code PT35M}, {@code PT1H30M}. */
    private static Integer minutes(String raw) {
        if (raw == null || raw.isBlank()) {
            return null;
        }
        try {
            return (int) Duration.parse(raw).toMinutes();
        } catch (java.time.format.DateTimeParseException e) {
            return null;
        }
    }

    private static String image(JsonNode node) {
        if (node == null) {
            return null;
        }
        if (node.isArray()) {
            return node.isEmpty() ? null : image(node.get(0));
        }
        if (node.isObject()) {
            return text(node.get("url"));
        }
        return node.asString(null);
    }

    /**
     * The instructions as a Markdown list.
     *
     * <p>Plain text, a list of strings, a list of {@code HowToStep} — and a list of
     * {@code HowToSection}, each with a name and its own steps. The sections were dropped
     * entirely before: they carry no {@code text} of their own, so a page that groups its
     * steps ("For the dough", "For the filling") came in without any preparation.
     */
    private static String instructions(JsonNode node) {
        if (node == null) {
            return null;
        }
        if (node.isString()) {
            return node.asString("");
        }
        if (!node.isArray()) {
            return null;
        }
        StringBuilder out = new StringBuilder();
        appendSteps(node, out);
        return out.isEmpty() ? null : out.toString();
    }

    private static void appendSteps(JsonNode steps, StringBuilder out) {
        for (JsonNode step : steps) {
            JsonNode section = step.isObject() ? step.get("itemListElement") : null;
            if (section != null && section.isArray()) {
                String name = text(step.get("name"));
                if (!out.isEmpty()) {
                    out.append("\n");
                }
                if (name != null && !name.isBlank()) {
                    out.append("### ").append(name.trim()).append("\n\n");
                }
                appendSteps(section, out);
                continue;
            }
            String line = step.isObject() ? text(step.get("text")) : step.asString(null);
            if (line != null && !line.isBlank()) {
                out.append("1. ").append(line.trim()).append("\n");
            }
        }
    }
}
