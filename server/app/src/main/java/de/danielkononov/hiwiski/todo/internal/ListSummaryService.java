package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.api.model.ListSummary;
import de.danielkononov.hiwiski.api.model.ListSummaryColumn;
import de.danielkononov.hiwiski.api.model.ListSummaryItem;
import de.danielkononov.hiwiski.db.generated.tables.records.TodoRecord;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.JSONB;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;

/**
 * What a home screen widget shows of a list: its open entries and how many are open and
 * done — or, on a Kanban board, the cards standing in one column.
 *
 * <p>The app reads its lists from its own database. The widget asks here because it
 * refreshes while the app is closed, and it must show what the list shows: the same
 * order (position, then title) and, on a board, the same derived column.
 *
 * <p><strong>Visibility is part of the query</strong>: a list the caller cannot see
 * answers like a missing one, and an entry with a share of its own that leaves the caller
 * out is not counted either.
 */
@Service
class ListSummaryService {

    static final int DEFAULT_LIMIT = 30;

    static final String LIST_NOT_FOUND = "todo.list_not_found";

    private static final String DONE = "DONE";

    private static final Logger LOG = LoggerFactory.getLogger(ListSummaryService.class);

    /**
     * Position, then title — sorted here and not in SQL: the database orders titles by
     * its collation, the app by code unit, and the widget must show the app's order. A
     * missing position counts as 0, as on the device.
     */
    private static final java.util.Comparator<TodoRecord> IN_LIST_ORDER = java.util.Comparator
            .<TodoRecord>comparingInt(todo -> todo.getPosition() == null ? 0 : todo.getPosition())
            .thenComparing(TodoRecord::getTitle);

    private final DSLContext db;
    private final ChangeVisibility visibility;
    private final ChangeSequence sequence;
    private final ObjectMapper mapper;

    ListSummaryService(DSLContext db, ChangeVisibility visibility, ChangeSequence sequence, ObjectMapper mapper) {
        this.db = db;
        this.visibility = visibility;
        this.sequence = sequence;
        this.mapper = mapper;
    }

    /** A board's column as stored on the list. */
    record Column(UUID id, String name, String colorToken, boolean done) {}

    /** @param columnId {@code null}: the open entries of the whole list */
    @Transactional(readOnly = true)
    ListSummary summary(UUID member, UUID listId, UUID columnId, int limit) {
        // Read before the list: the position may lag behind what is read, never run ahead
        // of it. The widget keeps whichever picture is newer.
        long position = sequence.current();

        var list = db.selectFrom(TODO_LIST)
                .where(TODO_LIST.ID.eq(listId))
                .and(TODO_LIST.DELETED_AT.isNull())
                .and(visibility.itemVisibleTo(member, TodoSyncTypes.TODO_LIST_TYPE, TODO_LIST.ID))
                .fetchOne();
        if (list == null) {
            throw HiwiskiException.notFound(LIST_NOT_FOUND, "listId", listId);
        }

        List<TodoRecord> todos = db.selectFrom(TODO)
                .where(TODO.LIST_ID.eq(listId))
                .and(TODO.DELETED_AT.isNull())
                .and(visibility.itemVisibleTo(member, TodoSyncTypes.TODO_TYPE, TODO.ID))
                .fetch()
                .stream()
                .sorted(IN_LIST_ORDER)
                .toList();

        int done = (int) todos.stream().filter(ListSummaryService::isDone).count();
        List<Column> columns = KanbanRules.KANBAN.equals(list.getKind()) ? columns(list.getColumns()) : List.of();
        Column column = columns.stream()
                .filter(candidate -> candidate.id().equals(columnId))
                .findFirst()
                .orElse(null);

        List<TodoRecord> shown = new ArrayList<>();
        for (TodoRecord todo : todos) {
            boolean wanted = column == null
                    ? !isDone(todo)
                    : column.id().equals(columnOf(todo, columns));
            if (wanted) {
                shown.add(todo);
            }
        }

        var summary = new ListSummary(
                position,
                list.getId(),
                list.getName(),
                list.getKind(),
                todos.size() - done,
                done,
                shown.stream().limit(limit).map(ListSummaryService::item).toList(),
                shown.size() > limit);
        summary.setColorToken(list.getColorToken());
        summary.setArchived(list.getArchivedAt() != null);
        if (column != null) {
            var shownColumn = new ListSummaryColumn(column.id(), column.name(), column.done());
            shownColumn.setColorToken(column.colorToken());
            shownColumn.setCount(shown.size());
            summary.setColumn(shownColumn);
        }
        return summary;
    }

    /**
     * The column a card <strong>stands in</strong> — derived as the app derives it, so
     * status and column never contradict each other: a done card stands in its column if
     * that is a done column, otherwise in the first done one; an open card likewise among
     * the open columns. A card whose column was deleted does not vanish.
     */
    static UUID columnOf(TodoRecord todo, List<Column> columns) {
        boolean done = isDone(todo);
        for (Column column : columns) {
            if (column.id().equals(todo.getColumnId()) && column.done() == done) {
                return column.id();
            }
        }
        return (done ? doneColumn(columns) : firstOpenColumn(columns)).id();
    }

    /** Where a card ticked off elsewhere goes; the last column if the data has no done one. */
    private static Column doneColumn(List<Column> columns) {
        return columns.stream().filter(Column::done).findFirst().orElse(columns.getLast());
    }

    /** Where an open card without a column goes; the first column if all are done ones. */
    private static Column firstOpenColumn(List<Column> columns) {
        return columns.stream().filter(column -> !column.done()).findFirst().orElse(columns.getFirst());
    }

    private static boolean isDone(TodoRecord todo) {
        return DONE.equals(todo.getStatus());
    }

    private static ListSummaryItem item(TodoRecord todo) {
        var item = new ListSummaryItem(todo.getId(), todo.getTitle(), isDone(todo));
        item.setAmount(todo.getAmount());
        item.setUnit(todo.getUnit());
        item.setDueDate(todo.getDueDate());
        if (todo.getDueTime() != null) {
            item.setDueTime(String.format("%02d:%02d", todo.getDueTime().getHour(), todo.getDueTime().getMinute()));
        }
        return item;
    }

    /** Tolerant, as in the app: a broken value costs the board its columns, not the call. */
    private List<Column> columns(JSONB raw) {
        if (raw == null || raw.data() == null) {
            return List.of();
        }
        try {
            Object parsed = mapper.readValue(raw.data(), Object.class);
            if (!(parsed instanceof List<?> entries)) {
                return List.of();
            }
            List<Column> columns = new ArrayList<>();
            for (Object entry : entries) {
                if (entry instanceof Map<?, ?> column && column.get("id") instanceof String id) {
                    columns.add(new Column(
                            UUID.fromString(id),
                            Objects.toString(column.get("name"), ""),
                            column.get("colorToken") instanceof String token ? token : null,
                            Boolean.TRUE.equals(column.get("done"))));
                }
            }
            return columns;
        } catch (JacksonException | IllegalArgumentException broken) {
            LOG.warn("Unreadable Kanban columns");
            return List.of();
        }
    }
}
