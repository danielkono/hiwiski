package de.danielkononov.hiwiski.wiki.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Reading a recipe from a page's structured data ({@code application/ld+json}).
 *
 * <p>When testing, imported recipes came in without their description, and pages that
 * group their steps into sections came in without any preparation at all.
 */
class RecipeImporterTest {

    private final RecipeImporter importer = new RecipeImporter(new IngredientParser());

    private static String page(String json) {
        return "<html><head><script type=\"application/ld+json\">" + json + "</script></head></html>";
    }

    @Test
    void theDescriptionComesBeforeTheSteps() {
        var recipe = importer.parse(page("""
                {"@type": "Recipe", "name": "Pumpkin soup",
                 "description": "Warming, quick, and good with bread.",
                 "recipeInstructions": [
                   {"@type": "HowToStep", "text": "Dice the pumpkin."},
                   {"@type": "HowToStep", "text": "Simmer for 20 minutes."}]}
                """), "https://example.org/soup");

        assertThat(recipe.content()).isEqualTo("""
                Warming, quick, and good with bread.

                1. Dice the pumpkin.
                1. Simmer for 20 minutes.
                """);
    }

    @Test
    void sectionsBecomeHeadingsWithTheirSteps() {
        var recipe = importer.parse(page("""
                {"@type": "Recipe", "name": "Plum cake",
                 "recipeInstructions": [
                   {"@type": "HowToSection", "name": "For the dough", "itemListElement": [
                     {"@type": "HowToStep", "text": "Knead flour and butter."}]},
                   {"@type": "HowToSection", "name": "For the topping", "itemListElement": [
                     {"@type": "HowToStep", "text": "Halve the plums."},
                     {"@type": "HowToStep", "text": "Spread them on the dough."}]}]}
                """), "https://example.org/cake");

        assertThat(recipe.content()).isEqualTo("""
                ### For the dough

                1. Knead flour and butter.

                ### For the topping

                1. Halve the plums.
                1. Spread them on the dough.
                """);
    }

    @Test
    void withoutATotalTimePreparationAndCookingAddUp() {
        var recipe = importer.parse(page("""
                {"@type": "Recipe", "name": "Risotto", "prepTime": "PT10M", "cookTime": "PT25M"}
                """), "https://example.org/risotto");

        assertThat(recipe.durationMinutes()).isEqualTo(35);
    }

    @Test
    void onlyLdJsonBlocksAreRead() {
        String html = """
                <SCRIPT src="app.js"></SCRIPT>
                <script>var x = "<script";</script>
                <script id="a" type='application/ld+json'>{"a": 1}</script>
                <script type=application/ld+json>{"b": 2}</script>
                <script type="text/javascript">{"c": 3}</script>
                """;

        assertThat(RecipeImporter.ldJsonBlocks(html)).containsExactly("{\"a\": 1}", "{\"b\": 2}");
    }

    // These pages imported with the old regex and not
    // with the first linear scan.
    @ParameterizedTest
    @ValueSource(strings = {
        "<!-- <script src=x> -->",
        "<scripty>",
        "<script-x>",
        "<template><script></template>",
        "<TEMPLATE id=t><script src=y></TEMPLATE>",
        "<p>use &lt;script&gt;</p><scripty>",
        "<script>var s='<script>';</script>",
        "<script>if(a<script){}</script>",
        "<!---->",
    })
    void theScanFindsWhatTheOldPatternFound(String before) {
        String html = before + "<script type=\"application/ld+json\">{\"@type\":\"Recipe\"}</script>";

        assertThat(RecipeImporter.ldJsonBlocks(html))
                .containsExactlyElementsOf(oldLdJsonBlocks(html))
                .containsExactly("{\"@type\":\"Recipe\"}");
    }

    @Test
    void aSelfClosedScriptRunsOnAsInABrowser() {
        // A browser ignores the "/" of <script/> and reads on to the next </script>; the
        // block after it is script text there, so it is not one here either.
        String html = "<script src=\"a.js\"/><script type=\"application/ld+json\">{}</script>";

        assertThat(RecipeImporter.ldJsonBlocks(html)).isEmpty();
    }

    /** The pattern before M9, as the reference for what a page delivers. */
    private static List<String> oldLdJsonBlocks(String html) {
        var old = Pattern.compile(
                "<script[^>]+type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>",
                Pattern.DOTALL | Pattern.CASE_INSENSITIVE);
        List<String> blocks = new ArrayList<>();
        var matcher = old.matcher(html);
        while (matcher.find()) {
            blocks.add(matcher.group(1));
        }
        return blocks;
    }

    @Test
    void theRecipeIsFoundAfterOtherBlocks() {
        String html = "<script type=\"application/ld+json\">{\"@type\": \"WebSite\"}</script>"
                + page("{\"@type\": \"Recipe\", \"name\": \"Soup\"}");

        assertThat(importer.parse(html, "https://example.org/soup").title()).isEqualTo("Soup");
    }

    // A page of unclosed "<script " took 24 s for 320 KB
    // and about an hour at the 4 MiB limit.
    @Test
    void aHostilePageIsScannedInLinearTime() {
        String unclosed = "<script ".repeat(4 * 1024 * 1024 / 8);
        String unterminated = "<script type='application/ld+json'>".repeat(4 * 1024 * 1024 / 36);

        String prefixes = "<scripty <template ".repeat(4 * 1024 * 1024 / 19);
        String comments = "<!-- -->".repeat(4 * 1024 * 1024 / 8);

        assertTimeoutPreemptively(Duration.ofSeconds(5), () -> {
            assertThatThrownBy(() -> importer.parse(unclosed, "https://example.org"))
                    .isInstanceOf(HiwiskiException.class);
            assertThatThrownBy(() -> importer.parse(unterminated, "https://example.org"))
                    .isInstanceOf(HiwiskiException.class);
            assertThat(RecipeImporter.ldJsonBlocks(prefixes)).isEmpty();
            assertThat(RecipeImporter.ldJsonBlocks(comments)).isEmpty();
        });
    }
}
