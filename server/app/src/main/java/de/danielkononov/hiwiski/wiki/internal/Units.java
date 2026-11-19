package de.danielkononov.hiwiski.wiki.internal;

import java.math.BigDecimal;
import java.util.Locale;
import java.util.Map;

/**
 * Units live <strong>in the code, not in the database</strong>.
 *
 * <p><strong>Conversion happens only exactly, within one dimension</strong> (g/kg,
 * ml/l). "1 Bund" (bunch) and "200 g" of parsley make two lines, and that is right: how
 * many grams a bunch weighs nobody knows, and an estimate would then sit on the
 * shopping list as a number.
 */
final class Units {

    private Units() {}

    /** Unit → (dimension, factor to the base unit). */
    private static final Map<String, Conversion> KNOWN = Map.of(
            "mg", new Conversion("mass", new BigDecimal("0.001")),
            "g", new Conversion("mass", BigDecimal.ONE),
            "kg", new Conversion("mass", new BigDecimal("1000")),
            "ml", new Conversion("volume", BigDecimal.ONE),
            "cl", new Conversion("volume", BigDecimal.TEN),
            "l", new Conversion("volume", new BigDecimal("1000")));

    private record Conversion(String dimension, BigDecimal factor) {}

    /**
     * Whether two units may be added up.
     *
     * <p>Two unknown units are the same dimension only if they have the <em>same</em>
     * name: "2 Bund" and "1 Bund" are three Bund, "1 Bund" and "1 Prise" are two lines.
     */
    static boolean sameDimension(String a, String b) {
        String left = normalize(a);
        String right = normalize(b);
        if (left == null || right == null) {
            return left == null && right == null;
        }
        Conversion one = KNOWN.get(left);
        Conversion two = KNOWN.get(right);
        if (one == null || two == null) {
            return left.equals(right);
        }
        return one.dimension().equals(two.dimension());
    }

    /** The value in the dimension's base unit, or unchanged if unknown. */
    static BigDecimal toBase(BigDecimal amount, String unit) {
        if (amount == null) {
            return null;
        }
        Conversion conversion = KNOWN.get(normalize(unit));
        return conversion == null ? amount : amount.multiply(conversion.factor());
    }

    private static String normalize(String unit) {
        return unit == null || unit.isBlank() ? null : unit.trim().toLowerCase(Locale.ROOT);
    }
}
