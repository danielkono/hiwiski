package de.danielkononov.hiwiski.sync;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;

/**
 * A field that is not a column of its own but a key in the type's property map
 * ({@link SyncType#propertiesColumn()}) — for what only some items of a type carry: a
 * recipe's servings on a wiki page.
 *
 * <p>On the wire and in the log it is a field like any other, under its own name, and
 * it goes through sync like one: <strong>its own sequence, its own conflict
 * check</strong>. Two devices changing servings and source at once both get through;
 * two changing the servings collide. Only the storage differs: a new kind of item with
 * new fields needs no column, no migration and no change in {@code sync}.
 *
 * @param name the name in the contract, {@code camelCase}; never one of the type's
 *     column fields
 * @param normalize the delivered JSON value to the one stored — checking it on the way
 */
public record SyncProperty(String name, Function<Object, Object> normalize) {

    /** Same as a column field: a value that does not fit is the mutation's fault. */
    public SyncProperty {
        Function<Object, Object> raw = normalize;
        normalize = value -> {
            if (value == null) {
                return null;
            }
            try {
                return raw.apply(value);
            } catch (IllegalArgumentException | ClassCastException | NullPointerException e) {
                throw HiwiskiException.invalid(SyncField.INVALID_FIELD, "field", name);
            }
        };
    }

    public static SyncProperty text(String name) {
        return new SyncProperty(name, value -> {
            String text = (String) value;
            SyncLimits.check(text.length() <= SyncLimits.TEXT_CHARS, name);
            return text;
        });
    }

    public static SyncProperty integer(String name) {
        return new SyncProperty(name, value -> {
            var number = (Number) value;
            if (number.doubleValue() != Math.rint(number.doubleValue())) {
                throw new IllegalArgumentException("not a whole number");
            }
            return number.intValue();
        });
    }

    public static SyncProperty decimal(String name) {
        return new SyncProperty(name, value -> new BigDecimal(value.toString()));
    }

    public static SyncProperty flag(String name) {
        return new SyncProperty(name, value -> (Boolean) value);
    }

    /** Stored as its text form; checked to be a UUID. */
    public static SyncProperty uuid(String name) {
        return new SyncProperty(name, value -> UUID.fromString((String) value).toString());
    }

    /**
     * A JSON list or object, <strong>replaced as a whole</strong> — like
     * {@link SyncField#json}: an ordered sequence two devices change at once is one
     * field, and merging it would yield a list nobody wrote.
     */
    public static SyncProperty json(String name) {
        return new SyncProperty(name, value -> {
            if (!(value instanceof List<?>) && !(value instanceof Map<?, ?>)) {
                throw new IllegalArgumentException("not a JSON list or object");
            }
            SyncLimits.check(
                    new tools.jackson.databind.ObjectMapper().writeValueAsString(value).length() <= SyncLimits.JSON_CHARS,
                    name);
            return value;
        });
    }
}
