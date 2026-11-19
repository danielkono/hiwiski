package de.danielkononov.hiwiski.todo.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_OCCURRENCE;

import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.access.JooqOwnable;
import de.danielkononov.hiwiski.access.Ownable;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code todo} registers with {@code access}: who owns, where it inherits from, who
 * is assigned.
 *
 * <p>The same inversion as with sync — {@code access} does not enumerate domain types.
 */
@Configuration
class TodoOwnables {

    @Bean
    Ownable todoListOwnable(DSLContext db) {
        // A list is a container and inherits from nobody.
        return new JooqOwnable(db, TodoSyncTypes.TODO_LIST_TYPE, TODO_LIST) {

            @Override
            public List<UUID> assigneesOf(UUID itemId) {
                UUID[] values = db().select(TODO_LIST.ASSIGNEES)
                        .from(TODO_LIST)
                        .where(TODO_LIST.ID.eq(itemId))
                        .fetchOne(TODO_LIST.ASSIGNEES);
                return values == null ? List.of() : Arrays.asList(values);
            }

            @Override
            public List<UUID> assignedTo(UUID subject) {
                return db().select(TODO_LIST.ID)
                        .from(TODO_LIST)
                        .where(TODO_LIST.ASSIGNEES.contains(new UUID[] {subject}))
                        .and(TODO_LIST.DELETED_AT.isNull())
                        .fetch(TODO_LIST.ID);
            }

            @Override
            public boolean checkable() {
                return true;
            }

            /** Assigning a list hands out *write* on it -- that is sharing, the owner's. */
            @Override
            public java.util.Set<String> ownerOnlyFields() {
                return java.util.Set.of("assignees");
            }

            /**
             * Assignees see the list automatically and may edit it — unlike the task, where assignment only means check off: whoever is
             * assigned a list is meant to fill it.
             */
            @Override
            public AccessLevel assignmentLevel() {
                return AccessLevel.WRITE;
            }
        };
    }

    @Bean
    Ownable todoOwnable(DSLContext db) {
        return new JooqOwnable(db, TodoSyncTypes.TODO_TYPE, TODO, TodoSyncTypes.TODO_LIST_TYPE, TODO.LIST_ID) {

            /** Members <em>and</em> groups — the assignment does not tell them apart. */
            @Override
            public List<UUID> assigneesOf(UUID itemId) {
                UUID[] values = db().select(TODO.ASSIGNEES)
                        .from(TODO)
                        .where(TODO.ID.eq(itemId))
                        .fetchOne(TODO.ASSIGNEES);
                return values == null ? List.of() : Arrays.asList(values);
            }

            @Override
            public List<UUID> ownerAssigneesOf(UUID itemId) {
                return uuids(itemId, TODO.OWNER_ASSIGNEES);
            }

            @Override
            public java.util.Optional<String> assigneeField() {
                return java.util.Optional.of("assignees");
            }

            @Override
            public void assignmentWritten(UUID itemId, java.util.Collection<UUID> chosenByOwner) {
                keepOwnerAssignees(itemId, TODO.ASSIGNEES, TODO.OWNER_ASSIGNEES, chosenByOwner);
            }

            @Override
            public List<UUID> assignedTo(UUID subject) {
                return db().select(TODO.ID)
                        .from(TODO)
                        .where(TODO.ASSIGNEES.contains(new UUID[] {subject}))
                        .and(TODO.DELETED_AT.isNull())
                        .fetch(TODO.ID);
            }

            @Override
            public boolean checkable() {
                return true;
            }

            /**
             * Whoever is assigned a task may check it off.
             *
             * <p>Not just read: a task assigned to someone who cannot check it off is a
             * message, not a task.
             */
            @Override
            public AccessLevel assignmentLevel() {
                return AccessLevel.CHECK;
            }
        };
    }

    @Bean
    Ownable todoOccurrenceOwnable(DSLContext db) {
        // An occurrence inherits from its task: whoever may check off the series may
        // also check off its individual dates.
        return new JooqOwnable(
                db,
                TodoSyncTypes.TODO_OCCURRENCE_TYPE,
                TODO_OCCURRENCE,
                TodoSyncTypes.TODO_TYPE,
                TODO_OCCURRENCE.TODO_ID) {

            /** Ticking a date off creates the occurrence; unticking deletes it. */
            @Override
            public AccessLevel placementLevel() {
                return AccessLevel.CHECK;
            }
        };
    }
}
