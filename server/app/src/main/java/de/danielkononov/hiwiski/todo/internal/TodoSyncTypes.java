package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_OCCURRENCE;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import de.danielkononov.hiwiski.recurrence.Recurrence;
import de.danielkononov.hiwiski.sync.Archive;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.jooq.TableField;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code todo} registers with sync.
 *
 * <p>That is the whole integration. {@code sync} knows no domain types; the domain
 * modules register themselves. That is exactly why the calendar
 * costs not a single line here.
 */
@Configuration
class TodoSyncTypes {

    static final String TODO_LIST_TYPE = "TODO_LIST";
    static final String TODO_TYPE = "TODO";
    static final String TODO_OCCURRENCE_TYPE = "TODO_OCCURRENCE";

    private final DSLContext db;
    private final Recurrence recurrence;

    TodoSyncTypes(DSLContext db, Recurrence recurrence) {
        this.db = db;
        this.recurrence = recurrence;
    }

    /** What a task's status can be; the devices know no third state. */
    private static final java.util.Set<String> STATUSES = java.util.Set.of("OPEN", "DONE");

    /**
     * A status the devices know, and a rule every device can expand -- as for an event.
     * A task took any rule: one the devices' library searches through without yielding
     * froze the task list of everyone the list is shared with.
     */
    private boolean readable(Map<String, Object> fields) {
        if (fields == null) {
            return true;
        }
        Object status = fields.get("status");
        if (status != null && !STATUSES.contains(status.toString())) {
            return false;
        }
        Object rrule = fields.get("rrule");
        // An empty rule is how a device ends a series.
        return rrule == null || rrule.toString().isBlank() || recurrence.accepts(rrule.toString());
    }

    /**
     * Whether the list is archived — and with it every task in it.
     *
     * <p>Tasks carry no flag of their own: archiving a list of forty tasks would otherwise
     * be forty changes, and a task added offline in the meantime would stay outside.
     */
    private boolean listArchived(UUID listId) {
        return listId != null
                && db.fetchExists(db.selectOne()
                        .from(TODO_LIST)
                        .where(TODO_LIST.ID.eq(listId))
                        .and(TODO_LIST.ARCHIVED_AT.isNotNull()));
    }

    private static UUID uuidField(Map<String, Object> fields, String name, UUID otherwise) {
        if (fields == null || !fields.containsKey(name)) {
            return otherwise;
        }
        Object value = fields.get(name);
        return value == null ? null : UUID.fromString(value.toString());
    }

    /** A list is a container: tasks inherit their share from it. */
    @Bean
    SyncType todoListSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return TODO_LIST_TYPE;
            }

            @Override
            public Table<?> table() {
                return TODO_LIST;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("name", TODO_LIST.NAME),
                        SyncField.text("description", TODO_LIST.DESCRIPTION),
                        // The kind can no longer be changed after creation; the UI does
                        // not offer it, and changing it would make amounts and aisles
                        // meaningless.
                        SyncField.text("kind", TODO_LIST.KIND),
                        SyncField.text("colorToken", TODO_LIST.COLOR_TOKEN),
                        SyncField.integer("position", TODO_LIST.POSITION),
                        SyncField.uuidArray("assignees", TODO_LIST.ASSIGNEES),
                        SyncField.uuidArray("tags", TODO_LIST.TAGS),
                        // Replaced as a whole: two devices reordering at the same time
                        // conflict instead of producing an order nobody chose.
                        SyncField.json("columns", TODO_LIST.COLUMNS),
                        SyncField.timestamp(Archive.ARCHIVED_AT, TODO_LIST.ARCHIVED_AT),
                        SyncField.uuid(Archive.ARCHIVED_BY, TODO_LIST.ARCHIVED_BY));
            }

            /**
             * An archived list is read-only; restoring is the one change it takes. The kind
             * changes only from task list to board, and a board keeps valid columns.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (exists && listArchived(entityId) && !Archive.onlyArchiveFields(fields)) {
                    return Optional.of(Archive.READ_ONLY);
                }
                var current = exists
                        ? db.select(TODO_LIST.KIND, TODO_LIST.COLUMNS)
                                .from(TODO_LIST)
                                .where(TODO_LIST.ID.eq(entityId))
                                .fetchOne()
                        : null;
                var refusal = KanbanRules.listRefusal(
                        current == null ? null : current.value1(), current == null ? null : current.value2(), fields);
                if (refusal.isPresent()) {
                    return refusal;
                }
                // Into a board only without repeats: in which column would the next one
                // stand? Converted with repeating tasks in it, the board held exactly the
                // repeating cards a board cannot have.
                boolean becomesBoard = fields != null
                        && KanbanRules.KANBAN.equals(fields.get("kind"))
                        && current != null
                        && !KanbanRules.KANBAN.equals(current.value1());
                if (becomesBoard && db.fetchExists(db.selectOne()
                        .from(TODO)
                        .where(TODO.LIST_ID.eq(entityId))
                        .and(TODO.DELETED_AT.isNull())
                        .and(TODO.RRULE.isNotNull())
                        .and(TODO.RRULE.ne("")))) {
                    return Optional.of(KanbanRules.NO_REPEAT);
                }
                return Optional.empty();
            }

            /**
             * With a list go its tasks -- and with them their occurrences. Left alive, the
             * tasks of a deleted list stayed in search, on assignees' devices and behind
             * their numbers, and restoring the list brought back nothing that had gone.
             */
            @Override
            public List<Ref> alsoDeleted(UUID entityId) {
                return db.select(TODO.ID)
                        .from(TODO)
                        .where(TODO.LIST_ID.eq(entityId))
                        .and(TODO.DELETED_AT.isNull())
                        .fetch(TODO.ID)
                        .stream()
                        .map(id -> new Ref(TODO_TYPE, id))
                        .toList();
            }

            @Override
            public Map<String, Object> stamped(UUID actor, java.time.OffsetDateTime now, Map<String, Object> fields) {
                return Archive.stamped(fields, actor, now);
            }

            /** A list is cited like a task: {@code LST-3}. */
            @Override
            public Optional<KeyedEntityType> keyType() {
                return Optional.of(KeyedEntityType.TODO_LIST);
            }

            @Override
            public Optional<TableField<?, String>> keyColumn() {
                return Optional.of(TODO_LIST.ENTITY_KEY);
            }
        };
    }

    @Bean
    SyncType todoSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return TODO_TYPE;
            }

            @Override
            public Table<?> table() {
                return TODO;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("title", TODO.TITLE),
                        SyncField.text("description", TODO.DESCRIPTION),
                        SyncField.text("status", TODO.STATUS),
                        SyncField.date("dueDate", TODO.DUE_DATE),
                        SyncField.time("dueTime", TODO.DUE_TIME),
                        SyncField.text("rrule", TODO.RRULE),
                        SyncField.uuidArray("assignees", TODO.ASSIGNEES),
                        SyncField.integer("position", TODO.POSITION),
                        SyncField.decimal("amount", TODO.AMOUNT),
                        SyncField.text("unit", TODO.UNIT),
                        SyncField.uuid("productId", TODO.PRODUCT_ID),
                        SyncField.uuidArray("tags", TODO.TAGS),
                        SyncField.uuid("columnId", TODO.COLUMN_ID));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(TODO_LIST_TYPE, TODO.LIST_ID));
            }

            /**
             * Nothing is added to, changed in or moved into an archived list — and nothing
             * on a board repeats.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (!readable(fields)) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                UUID current = exists
                        ? db.select(TODO.LIST_ID).from(TODO).where(TODO.ID.eq(entityId)).fetchOne(TODO.LIST_ID)
                        : null;
                UUID target = uuidField(fields, "listId", containerId);
                if (listArchived(current) || listArchived(target)) {
                    return Optional.of(Archive.READ_ONLY);
                }
                UUID list = target != null ? target : current;
                String kind = list == null
                        ? null
                        : db.select(TODO_LIST.KIND).from(TODO_LIST).where(TODO_LIST.ID.eq(list)).fetchOne(TODO_LIST.KIND);
                return KanbanRules.todoRefusal(kind, fields);
            }

            /** With a task go its checked-off occurrences. */
            @Override
            public List<Ref> alsoDeleted(UUID entityId) {
                return db.select(TODO_OCCURRENCE.ID)
                        .from(TODO_OCCURRENCE)
                        .where(TODO_OCCURRENCE.TODO_ID.eq(entityId))
                        .and(TODO_OCCURRENCE.DELETED_AT.isNull())
                        .fetch(TODO_OCCURRENCE.ID)
                        .stream()
                        .map(id -> new Ref(TODO_OCCURRENCE_TYPE, id))
                        .toList();
            }

            @Override
            public Optional<KeyedEntityType> keyType() {
                return Optional.of(KeyedEntityType.TODO);
            }

            @Override
            public Optional<TableField<?, String>> keyColumn() {
                return Optional.of(TODO.ENTITY_KEY);
            }
        };
    }

    /**
     * A checked-off occurrence of a series is an <strong>entity of its own</strong>.
     *
     * <p>Done occurrences are merged in, not replaced: two devices that check off
     * different occurrences offline both get through. As a field on the task the list
     * would count as a whole, and the second device would overwrite the first one's
     * check mark -- exactly what an earlier version forgot for {@code event.exceptions}.
     */
    @Bean
    SyncType todoOccurrenceSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return TODO_OCCURRENCE_TYPE;
            }

            @Override
            public Table<?> table() {
                return TODO_OCCURRENCE;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.date("occurrenceDate", TODO_OCCURRENCE.OCCURRENCE_DATE),
                        SyncField.timestamp("doneAt", TODO_OCCURRENCE.DONE_AT),
                        SyncField.uuid("doneBy", TODO_OCCURRENCE.DONE_BY),
                        SyncField.flag("skipped", TODO_OCCURRENCE.SKIPPED));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(TODO_TYPE, TODO_OCCURRENCE.TODO_ID));
            }

            /** Who ticked a date off is whoever pushed it -- not a name the client chose. */
            @Override
            public Map<String, Object> stamped(UUID actor, java.time.OffsetDateTime now, Map<String, Object> fields) {
                return SyncType.stamp(fields, "doneBy", "doneAt", actor, now);
            }

            /** An occurrence of a task in an archived list is not checked off any more. */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                UUID todoId = uuidField(fields, "todoId", containerId);
                if (todoId == null && exists) {
                    todoId = db.select(TODO_OCCURRENCE.TODO_ID)
                            .from(TODO_OCCURRENCE)
                            .where(TODO_OCCURRENCE.ID.eq(entityId))
                            .fetchOne(TODO_OCCURRENCE.TODO_ID);
                }
                UUID listId = todoId == null
                        ? null
                        : db.select(TODO.LIST_ID).from(TODO).where(TODO.ID.eq(todoId)).fetchOne(TODO.LIST_ID);
                return listArchived(listId) ? Optional.of(Archive.READ_ONLY) : Optional.empty();
            }
        };
    }
}
