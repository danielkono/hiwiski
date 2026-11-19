package de.danielkononov.hiwiski.sync;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.math.BigDecimal;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import java.util.function.Function;
import org.jooq.Field;

/**
 * A field of a synced entity: its name in the contract, its column and the way between
 * JSON and the database.
 *
 * <p>The conversion lives here and not in the domain module because it is the same for
 * every entity. What a domain module contributes is the list of its fields -- not the
 * code that writes them.
 *
 * @param name the name in the contract, {@code camelCase}
 * @param column the column
 * @param decode JSON value to column value
 * @param encode column value to JSON value
 */
public record SyncField<T>(
        String name,
        Field<T> column,
        Function<Object, T> decode,
        Function<T, Object> encode,
        boolean merging) {

    /**
     * A value that does not fit the field is the mutation's fault, not the server's.
     *
     * <p>{@code position: "3"} or {@code dueDate: "tomorrow"} used to escape as a
     * {@code ClassCastException} or a parse error. That failed the whole push with a 500,
     * the device sent the same batch again and failed at the same mutation every time --
     * its outbox never drained. Now it is a rejection of that one mutation.
     */
    public SyncField {
        Function<Object, T> raw = decode;
        decode = value -> {
            try {
                return raw.apply(value);
            } catch (IllegalArgumentException | ClassCastException | DateTimeException | NullPointerException e) {
                // A null where a value has to be is bad input as well -- a `null` in a
                // list of ids escaped as a 500 and jammed the device's outbox.
                throw HiwiskiException.invalid(INVALID_FIELD, "field", name);
            }
        };
    }

    /** The code for a value that does not fit its field. */
    public static final String INVALID_FIELD = "sync.invalid_field";

    public SyncField(String name, Field<T> column, Function<Object, T> decode, Function<T, Object> encode) {
        this(name, column, decode, encode, false);
    }

    /**
     * A collection filled by several devices.
     *
     * <p>It is <strong>merged in, not replaced</strong>, and it bypasses the conflict
     * check: two devices that add different keys offline both get through.
     *
     * <p>"Replacing a list as a whole loses work. Every collection filled by several
     * devices needs this question."
     * An earlier version got it right for {@code todo_occurrence} and
     * forgot it for {@code event.exceptions} — there the list counted as a whole, and the
     * second device overwrote the first one's cancellation.
     */
    public static SyncField<org.jooq.JSONB> mergedMap(String name, Field<org.jooq.JSONB> column) {
        return new SyncField<>(
                name,
                column,
                value -> {
                    SyncLimits.check(
                            !(value instanceof java.util.Map<?, ?> map)
                                    || map.size() <= SyncLimits.MERGED_KEYS,
                            name);
                    return org.jooq.JSONB.valueOf(
                            value == null ? "{}" : new tools.jackson.databind.ObjectMapper().writeValueAsString(value));
                },
                value -> value == null || value.data() == null
                        ? java.util.Map.of()
                        : new tools.jackson.databind.ObjectMapper()
                                .readValue(value.data(), java.util.Map.class),
                true);
    }

    /**
     * A JSON value that is replaced <strong>as a whole</strong>.
     *
     * <p>The counterpart to {@link #mergedMap}: there the collection is a set that
     * several devices fill independently; here it is an ordered sequence, and two devices
     * changing line 3 at the same time mean the same field. Merging would yield a list
     * nobody wrote.
     *
     * <p>"Every collection filled by several devices needs this question."
     * — here the answer is: replace.
     */
    public static SyncField<org.jooq.JSONB> json(String name, Field<org.jooq.JSONB> column) {
        return new SyncField<>(
                name,
                column,
                value -> {
                    if (value == null) {
                        return null;
                    }
                    String text = new tools.jackson.databind.ObjectMapper().writeValueAsString(value);
                    SyncLimits.check(text.length() <= SyncLimits.JSON_CHARS, name);
                    return org.jooq.JSONB.valueOf(text);
                },
                value -> value == null || value.data() == null
                        ? null
                        : new tools.jackson.databind.ObjectMapper().readValue(value.data(), Object.class),
                false);
    }

    public static SyncField<String> text(String name, Field<String> column) {
        return new SyncField<>(
                name,
                column,
                value -> {
                    if (value == null) {
                        return null;
                    }
                    String text = value.toString();
                    SyncLimits.check(text.length() <= SyncLimits.TEXT_CHARS, name);
                    return text;
                },
                value -> value);
    }

    public static SyncField<Integer> integer(String name, Field<Integer> column) {
        return new SyncField<>(
                name, column, value -> value == null ? null : wholeNumber(name, value), value -> value);
    }

    /**
     * The value as an {@code int} -- if it is one. Cut to fit, a position of
     * 99999999999999999999 was stored as 1661992959 and 1.5 as 1, each answered
     * "applied": the device kept a value the server never took.
     */
    private static Integer wholeNumber(String name, Object value) {
        try {
            return new BigDecimal(((Number) value).toString()).intValueExact();
        } catch (ArithmeticException | NumberFormatException e) {
            throw HiwiskiException.invalid(INVALID_FIELD, "field", name);
        }
    }

    public static SyncField<Boolean> flag(String name, Field<Boolean> column) {
        return new SyncField<>(name, column, value -> value == null ? null : (Boolean) value, value -> value);
    }

    public static SyncField<BigDecimal> decimal(String name, Field<BigDecimal> column) {
        return new SyncField<>(
                name,
                column,
                value -> value == null ? null : new BigDecimal(value.toString()),
                // As a number, the way the client sends it: as text, the client failed
                // on the server value of a conflict and on the snapshot.
                value -> value);
    }

    public static SyncField<UUID> uuid(String name, Field<UUID> column) {
        return new SyncField<>(
                name,
                column,
                value -> value == null ? null : UUID.fromString(value.toString()),
                value -> value == null ? null : value.toString());
    }

    public static SyncField<LocalDate> date(String name, Field<LocalDate> column) {
        return new SyncField<>(
                name,
                column,
                value -> value == null ? null : LocalDate.parse(value.toString()),
                value -> value == null ? null : value.toString());
    }

    /** Local time without a zone, {@code HH:mm} -- that is how the contract has it. */
    public static SyncField<LocalTime> time(String name, Field<LocalTime> column) {
        return new SyncField<>(
                name,
                column,
                value -> value == null ? null : LocalTime.parse(value.toString()),
                value -> value == null ? null : value.toString().substring(0, 5));
    }

    public static SyncField<OffsetDateTime> timestamp(String name, Field<OffsetDateTime> column) {
        return new SyncField<>(
                name,
                column,
                value -> value == null ? null : OffsetDateTime.parse(value.toString()),
                value -> value == null ? null : value.toString());
    }

    /** Members <em>and</em> groups -- the assignment does not tell them apart. */
    public static SyncField<UUID[]> uuidArray(String name, Field<UUID[]> column) {
        return new SyncField<>(
                name,
                column,
                value -> {
                    if (value == null) {
                        return new UUID[0];
                    }
                    List<?> values = (List<?>) value;
                    SyncLimits.check(values.size() <= SyncLimits.IDS, name);
                    return values.stream()
                            .map(entry -> {
                                if (entry == null) {
                                    // Not a member nor a group: bad input, not a 500.
                                    throw new IllegalArgumentException("null in " + name);
                                }
                                return UUID.fromString(entry.toString());
                            })
                            .toArray(UUID[]::new);
                },
                value -> value == null ? List.of() : Arrays.stream(value).map(UUID::toString).toList());
    }
}
