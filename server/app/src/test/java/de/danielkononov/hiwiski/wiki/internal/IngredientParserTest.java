package de.danielkononov.hiwiski.wiki.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import java.math.BigDecimal;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * "{@code recipeIngredient} is free text and never parses completely; the review screen is
 * therefore <strong>mandatory, not a convenience</strong>."
 *
 * <p>So both are tested: that the clear cases split cleanly — and that the unclear ones are
 * <em>marked</em> as unclear rather than guessed. A parser that guesses produces "1 Prise"
 * from "Salz nach Geschmack", and nobody checks because it looks plausible.
 */
class IngredientParserTest {

    private final IngredientParser parser = new IngredientParser();

    @Test
    void amountUnitProduct() {
        var parsed = parser.parse("200 g Mehl");

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("200"));
        assertThat(parsed.unit()).isEqualTo("g");
        assertThat(parsed.label()).isEqualTo("Mehl");
        assertThat(parsed.uncertain()).isFalse();
    }

    @Test
    void decimalComma() {
        var parsed = parser.parse("1,5 l Brühe");

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("1.5"));
        assertThat(parsed.unit()).isEqualTo("l");
    }

    @Test
    void fraction() {
        var parsed = parser.parse("1/2 TL Salz");

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("0.500"));
        assertThat(parsed.unit()).isEqualTo("tl");
        assertThat(parsed.label()).isEqualTo("Salz");
    }

    @Test
    void fractionCharacter() {
        // "½ Zwiebel" appears exactly like this in every other recipe.
        var parsed = parser.parse("½ Zwiebel");

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("0.500"));
        assertThat(parsed.label()).isEqualTo("Zwiebel");
    }

    // "1½ l Milch" became "11/2 l Milch": 5.5 litres, not flagged.
    @ParameterizedTest
    @ValueSource(strings = {"1½ l Milch", "1 ½ l Milch", "1 1/2 l Milch"})
    void aMixedNumberIsOneAndAHalf(String line) {
        var parsed = parser.parse(line);

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("1.5"));
        assertThat(parsed.unit()).isEqualTo("l");
        assertThat(parsed.label()).isEqualTo("Milch");
        assertThat(parsed.uncertain()).isFalse();
    }

    @Test
    void aProductStartingWithANumberIsMarked() {
        assertThat(parser.parse("2 3 Eier").uncertain()).isTrue();
    }

    @Test
    void withoutUnit() {
        var parsed = parser.parse("2 Eier");

        assertThat(parsed.amount()).isEqualByComparingTo(new BigDecimal("2"));
        assertThat(parsed.unit()).describedAs("\"Eier\" is not a unit").isNull();
        assertThat(parsed.label()).isEqualTo("Eier");
        assertThat(parsed.uncertain()).isFalse();
    }

    @Test
    void theFirstWordIsNotAlwaysAUnit() {
        var parsed = parser.parse("2 Zwiebeln, gewürfelt");

        assertThat(parsed.unit()).isNull();
        assertThat(parsed.label()).isEqualTo("Zwiebeln, gewürfelt");
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "Salz nach Geschmack",
        "etwas Öl",
        "Pfeffer",
        "1 EL Öl (oder Butter)",
        "2 TL Zucker oder Honig"
    })
    void whatDoesNotSplitReliablyIsMarked(String line) {
        // Marked, not guessed. The review screen shows exactly these lines.
        assertThat(parser.parse(line).uncertain()).isTrue();
    }

    @Test
    void oneBunchAndTwoHundredGramsOfParsleyAreTwoLines() {
        // "1 Bund" and "200 g" of parsley make two lines.
        //
        // **Conversion happens only exactly within one dimension** (g/kg, ml/l).
        // "Bund" (bunch) is not a unit of mass -- nobody knows how many
        // grams a bunch has, and an estimate would then sit there as a number.
        var bunch = parser.parse("1 Bund Petersilie");
        var grams = parser.parse("200 g Petersilie");

        assertThat(bunch.label()).isEqualTo("Petersilie");
        assertThat(grams.label()).isEqualTo("Petersilie");
        assertThat(bunch.unit()).isEqualTo("bund");
        assertThat(grams.unit()).isEqualTo("g");
        assertThat(Units.sameDimension(bunch.unit(), grams.unit()))
                .describedAs("different dimensions -- so two lines")
                .isFalse();
    }

    @Test
    void gramsAndKilogramsAreOneLine() {
        assertThat(Units.sameDimension("g", "kg")).isTrue();
        assertThat(Units.toBase(new BigDecimal("1.5"), "kg")).isEqualByComparingTo(new BigDecimal("1500"));
        assertThat(Units.sameDimension("ml", "l")).isTrue();
    }

    @Test
    void emptyLine() {
        assertThat(parser.parse("").uncertain()).isTrue();
        assertThat(parser.parse(null).uncertain()).isTrue();
    }

    // One 3 KB line that cannot match took 28 s.
    @Test
    void aHostileLineIsParsedInLinearTime() {
        String line = "1" + " ".repeat(100_000) + " x\u2028";

        var parsed = assertTimeoutPreemptively(Duration.ofMillis(500), () -> parser.parse(line));

        assertThat(parsed.amount()).isNull();
        assertThat(parsed.uncertain()).isTrue();
    }

    // The fraction regex took 16 s for 40,000 digits.
    @Test
    void aLongDigitRunIsExpandedInLinearTime() {
        String digits = "1".repeat(1_000_000);
        String spaced = "1 ".repeat(500_000);
        String mixed = "1½".repeat(500_000);

        assertTimeoutPreemptively(Duration.ofSeconds(5), () -> {
            assertThat(IngredientParser.expandFractions(digits)).isEqualTo(digits);
            assertThat(IngredientParser.expandFractions(spaced)).isEqualTo(spaced);
            assertThat(IngredientParser.expandFractions(digits + "½")).isEqualTo(digits + " 1/2");
            assertThat(IngredientParser.expandFractions(mixed)).isEqualTo("1 1/2".repeat(500_000));
        });
    }

    @Test
    void anOverlongLineIsKeptCutAndMarked() {
        String line = "1".repeat(4_000_000);

        var parsed = assertTimeoutPreemptively(Duration.ofSeconds(2), () -> parser.parse(line));

        assertThat(parsed.amount()).isNull();
        assertThat(parsed.label()).hasSize(IngredientParser.MAX_LINE);
        assertThat(parsed.uncertain()).isTrue();
    }

    @Test
    void theScanExpandsFractionsLikeTheOldPattern() {
        char[] alphabet = {'1', '2', ' ', '\t', '½', '¾', 'a', '/', ' ', ' '};
        var random = new java.util.Random(20261101);
        for (int round = 0; round < 50_000; round++) {
            var text = new StringBuilder();
            int length = random.nextInt(12);
            for (int i = 0; i < length; i++) {
                text.append(alphabet[random.nextInt(alphabet.length)]);
            }
            String input = text.toString();
            assertThat(IngredientParser.expandFractions(input))
                    .describedAs("expanding \"%s\"", input)
                    .isEqualTo(oldExpandFractions(input));
        }
    }

    /** The pattern before R3, as the reference the scan must agree with. */
    private static String oldExpandFractions(String value) {
        var fractions = java.util.Map.of(
                '½', "1/2", '⅓', "1/3", '⅔', "2/3", '¼', "1/4", '¾', "3/4", '⅕', "1/5", '⅛', "1/8");
        var old = java.util.regex.Pattern.compile("(?:(\\d+)\\s*)?([½⅓⅔¼¾⅕⅛])");
        return old.matcher(value).replaceAll(match -> {
            String fraction = fractions.get(match.group(2).charAt(0));
            String whole = match.group(1);
            return java.util.regex.Matcher.quoteReplacement(whole == null ? fraction : whole + " " + fraction);
        });
    }
}
