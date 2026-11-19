package de.danielkononov.hiwiski.todo.internal;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.jooq.JSONB;
import tools.jackson.databind.ObjectMapper;

/**
 * What a Kanban board accepts.
 *
 * <p>The rules sit on the server and not only in the app: a board with one column, or
 * without a done or an open column, would show its cards in a place nobody can reason
 * about, and a device
 * that was offline during a conversion must not keep writing repeats into a board.
 */
final class KanbanRules {

    static final String STANDARD = "STANDARD";
    static final String SHOPPING = "SHOPPING";
    static final String KANBAN = "KANBAN";

    /** The kinds the clients know. */
    static final Set<String> KINDS = Set.of(STANDARD, SHOPPING, KANBAN);

    /** Fewer is no board; more does not fit next to each other on a laptop. */
    static final int MIN_COLUMNS = 2;

    static final int MAX_COLUMNS = 8;

    static final String KIND_LOCKED = "todo.kind_locked";
    static final String KIND_INVALID = "todo.kind_invalid";
    static final String COLUMNS_INVALID = "todo.kanban_columns_invalid";
    static final String NO_REPEAT = "todo.kanban_no_repeat";

    private static final ObjectMapper JSON = new ObjectMapper();

    private KanbanRules() {}

    /**
     * Why a list mutation is refused — or empty.
     *
     * @param currentKind the list's kind, {@code null} for a new list
     * @param currentColumns the list's columns as stored, {@code null} if none
     * @param fields the fields of the mutation
     */
    static Optional<String> listRefusal(String currentKind, JSONB currentColumns, Map<String, Object> fields) {
        Map<String, Object> changes = fields == null ? Map.of() : fields;
        String kind = currentKind;
        if (changes.containsKey("kind")) {
            // A kind no client knows could never become a board afterwards: the kind is
            // locked once set.
            if (!(changes.get("kind") instanceof String sent) || !KINDS.contains(sent)) {
                return Optional.of(KIND_INVALID);
            }
            kind = sent;
        }
        if (kind == null) {
            kind = STANDARD;
        }

        // Once and only in this direction: a task list may become a board.
        if (currentKind != null && !currentKind.equals(kind) && !(STANDARD.equals(currentKind) && KANBAN.equals(kind))) {
            return Optional.of(KIND_LOCKED);
        }

        if (!KANBAN.equals(kind)) {
            return Optional.empty();
        }
        Object columns = changes.containsKey("columns") ? changes.get("columns") : parse(currentColumns);
        return validColumns(columns) ? Optional.empty() : Optional.of(COLUMNS_INVALID);
    }

    /** A task on a board carries no repeat — in which column would the next one stand? */
    static Optional<String> todoRefusal(String listKind, Map<String, Object> fields) {
        if (!KANBAN.equals(listKind) || fields == null) {
            return Optional.empty();
        }
        Object rrule = fields.get("rrule");
        return rrule != null && !rrule.toString().isBlank() ? Optional.of(NO_REPEAT) : Optional.empty();
    }

    /**
     * 2 to 8 columns, distinct ids, a name each, at least one done column and at least one
     * open one -- several done columns ("Done", "Archived") are fine: a card in any of them
     * is done.
     */
    static boolean validColumns(Object value) {
        if (!(value instanceof List<?> columns) || columns.size() < MIN_COLUMNS || columns.size() > MAX_COLUMNS) {
            return false;
        }
        Set<UUID> ids = new HashSet<>();
        int done = 0;
        for (Object element : columns) {
            if (!(element instanceof Map<?, ?> column)) {
                return false;
            }
            UUID id;
            try {
                id = UUID.fromString(String.valueOf(column.get("id")));
            } catch (IllegalArgumentException notAnId) {
                return false;
            }
            if (!ids.add(id)) {
                return false;
            }
            if (!(column.get("name") instanceof String name) || name.isBlank()) {
                return false;
            }
            if (Boolean.TRUE.equals(column.get("done"))) {
                done++;
            }
        }
        return done >= 1 && done < columns.size();
    }

    private static Object parse(JSONB columns) {
        return columns == null || columns.data() == null ? null : JSON.readValue(columns.data(), Object.class);
    }
}
