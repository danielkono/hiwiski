package de.danielkononov.hiwiski.wiki.internal;

import java.math.BigDecimal;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

/**
 * Splits an ingredient line into amount, unit and product.
 *
 * <p><strong>{@code recipeIngredient} is free text and never fully adds up</strong>.
 * What could not be split reliably is therefore <em>flagged</em>
 * and not guessed — the review screen is mandatory, not a convenience.
 *
 * <p>The difference matters: a parser that guesses produces "0,5 Zwiebeln" from "eine
 * halbe Zwiebel" and "1 Prise" from "Salz nach Geschmack" — and nobody checks, because
 * it looks plausible.
 */
@Component
class IngredientParser {

    /**
     * {@code 200 g Mehl}, {@code 1/2 TL Salz}, {@code 1,5 l Brühe} -- and the mixed
     * {@code 1 1/2 TL Salz}, which read as amount 1 with "1/2 TL Salz" as the product.
     *
     * <p><strong>Linear time.</strong> The earlier form, {@code \s*(unit)?\s+(.+)$}, put
     * three overlapping quantifiers side by side: a line that could not match (a U+2028 at
     * its end) took 28 s for 3 KB. Now every run of
     * whitespace and digits is possessive, and the unit is only taken when whitespace
     * follows it — there is one way to split a line, so a failing match fails at once.
     */
    private static final Pattern LINE = Pattern.compile(
            "^\\s*+(?<amount>\\d++\\s++\\d++\\s*+/\\s*+\\d++|\\d++(?:[.,]\\d++)?(?:\\s*+/\\s*+\\d++)?)"
                    + "(?:\\s*+(?<unit>[a-zA-ZäöüÄÖÜß.]{1,12}+)(?=\\s))?+\\s++(?<label>.+)$");

    /** {@code ½ Zwiebel} — fraction characters are common in recipes. */
    private static final Map<Character, String> FRACTIONS = Map.of(
            '½', "1/2", '⅓', "1/3", '⅔', "2/3", '¼', "1/4", '¾', "3/4", '⅕', "1/5", '⅛', "1/8");

    /**
     * A line longer than this is no ingredient: it is kept, cut to this length, and flagged
     * without being parsed. It bounds the work per line however the parser is built.
     */
    static final int MAX_LINE = 500;

    /** A product that still starts with a number or fraction was not split right. */
    private static final Pattern LEFTOVER_AMOUNT = Pattern.compile("^[\\d½⅓⅔¼¾⅕⅛]");

    /**
     * Units live <strong>in the code, not in the database</strong>.
     */
    private static final List<String> UNITS = List.of(
            "g", "kg", "mg", "ml", "l", "cl", "tl", "el", "prise", "bund", "stück", "stk",
            "packung", "pck", "dose", "zehe", "blatt", "scheibe", "tasse", "becher", "msp");

    /**
     * @param uncertain true if the line could not be split reliably
     */
    record Parsed(BigDecimal amount, String unit, String label, boolean uncertain) {}

    Parsed parse(String raw) {
        if (raw == null || raw.isBlank()) {
            return new Parsed(null, null, "", true);
        }

        String trimmed = raw.trim();
        if (trimmed.length() > MAX_LINE) {
            return new Parsed(null, null, trimmed.substring(0, MAX_LINE), true);
        }

        String line = expandFractions(trimmed);
        var match = LINE.matcher(line);
        if (!match.matches()) {
            // No leading number: "Salz nach Geschmack", "etwas Öl". That is a valid
            // ingredient -- just without an amount. Flagged so that someone looks at it.
            return new Parsed(null, null, line, true);
        }

        BigDecimal amount = amount(match.group("amount"));
        String unit = match.group("unit");
        String label = match.group("label").trim();

        if (unit != null && !UNITS.contains(unit.toLowerCase(Locale.ROOT).replace(".", ""))) {
            // What looked like a unit was the first word of the product:
            // "2 Zwiebeln, gewuerfelt".
            label = unit + " " + label;
            unit = null;
        }

        boolean uncertain = amount == null
                // A line with an amount but no known unit is often fine ("2 Eier") --
                // one with a parenthetical or "oder" ("or") rarely is.
                || label.contains("oder ")
                || label.contains("(")
                || LEFTOVER_AMOUNT.matcher(label).find();

        return new Parsed(amount, unit == null ? null : unit.toLowerCase(Locale.ROOT), label, uncertain);
    }

    /**
     * A fraction character as a fraction -- added to a whole number right before it.
     *
     * <p>{@code 1½} used to become {@code 11/2}: 5.5 litres of milk, not flagged. And
     * {@code 1 ½} amount 1 with "1/2 l Milch" as the product. Both are 1 1/2 now.
     *
     * <p><strong>A plain scan, not a regex.</strong> {@code (?:(\d+)\s*)?([½…])} with
     * {@code replaceAll} tried every digit of a run as a start and ran each to the end of
     * the run: quadratic, 16 s for 40,000 digits. Here each
     * fraction character looks back over the whitespace and digits before it, never past
     * the previous replacement, so every character is looked at a bounded number of times.
     * The result is the regex's: the whole digit run right before the fraction character,
     * with any ASCII whitespace in between, becomes "whole fraction".
     */
    static String expandFractions(String value) {
        StringBuilder out = null;
        int copied = 0;
        for (int at = 0; at < value.length(); at++) {
            String fraction = FRACTIONS.get(value.charAt(at));
            if (fraction == null) {
                continue;
            }
            if (out == null) {
                out = new StringBuilder(value.length() + 8);
            }
            int digitsEnd = at;
            while (digitsEnd > copied && isAsciiWhitespace(value.charAt(digitsEnd - 1))) {
                digitsEnd--;
            }
            int digitsStart = digitsEnd;
            while (digitsStart > copied && isAsciiDigit(value.charAt(digitsStart - 1))) {
                digitsStart--;
            }
            if (digitsStart == digitsEnd) {
                // No whole number: only the character itself is replaced.
                out.append(value, copied, at).append(fraction);
            } else {
                out.append(value, copied, digitsEnd).append(' ').append(fraction);
            }
            copied = at + 1;
        }
        return out == null ? value : out.append(value, copied, value.length()).toString();
    }

    /** What {@code \s} matches without {@code UNICODE_CHARACTER_CLASS}. */
    private static boolean isAsciiWhitespace(char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\u000B' || c == '\f' || c == '\r';
    }

    /** What {@code \d} matches without {@code UNICODE_CHARACTER_CLASS}. */
    private static boolean isAsciiDigit(char c) {
        return c >= '0' && c <= '9';
    }

    private static BigDecimal amount(String raw) {
        String[] mixed = raw.trim().split("\\s+", 2);
        if (mixed.length == 2 && mixed[1].contains("/")) {
            BigDecimal whole = amount(mixed[0]);
            BigDecimal fraction = amount(mixed[1]);
            return whole == null || fraction == null ? null : whole.add(fraction);
        }
        String value = raw.replace(",", ".").replace(" ", "");
        try {
            if (value.contains("/")) {
                String[] parts = value.split("/");
                return new BigDecimal(parts[0])
                        .divide(new BigDecimal(parts[1]), 3, java.math.RoundingMode.HALF_UP);
            }
            return new BigDecimal(value);
        } catch (ArithmeticException | NumberFormatException e) {
            return null;
        }
    }
}
