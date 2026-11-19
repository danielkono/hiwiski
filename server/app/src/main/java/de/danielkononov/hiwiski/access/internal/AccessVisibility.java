package de.danielkononov.hiwiski.access.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;
import static de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS;

import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.sync.ChangeVisibility;
import java.util.UUID;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Component;

/**
 * The visibility check, fulfilled against {@code effective_access}.
 *
 * <p><strong>{@code access} points to {@code sync}, not the other way round.</strong>
 * {@code sync} declares the interface, {@code access} fulfills it — and thereby replaces
 * the default without anything changing in {@code sync}.
 */
@Component
class AccessVisibility implements ChangeVisibility {

    private final DSLContext db;
    private final EffectiveAccessService effective;
    private final AccessService access;

    AccessVisibility(DSLContext db, EffectiveAccessService effective, AccessService access) {
        this.db = db;
        this.effective = effective;
        this.access = access;
    }

    /**
     * A log entry is visible if the member may see the item.
     *
     * <p>As an {@code exists} against {@code effective_access} and <strong>in the same
     * query</strong> as the hits. Two steps would be a time window, and even a title
     * reveals too much.
     *
     * <p>Synthetic entries only go to their recipient: they are in the log with the
     * recipient's member ID, and anyone else seeing them would learn what was shared with
     * whom.
     */
    @Override
    public Condition visibleTo(UUID memberId) {
        Condition ownAccess = DSL.exists(db.selectOne()
                .from(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(memberId))
                .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(CHANGE_LOG.ENTITY_TYPE))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(CHANGE_LOG.ENTITY_ID)));

        Condition synthetic = CHANGE_LOG
                .OP
                .in("access_granted", "access_revoked")
                .and(CHANGE_LOG.ACTOR_MEMBER_ID.eq(memberId));

        Condition ordinary = CHANGE_LOG.OP.notIn("access_granted", "access_revoked").and(ownAccess);

        // A revocation has to arrive even when the access is already gone -- otherwise
        // the device would never learn about it and would keep the data.
        return ordinary.or(synthetic);
    }

    /** Like {@link #visibleTo}, for a row of the entity table instead of the log. */
    @Override
    public Condition itemVisibleTo(UUID memberId, String entityType, Field<UUID> itemId) {
        return DSL.exists(db.selectOne()
                .from(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(memberId))
                .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(entityType))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(itemId)));
    }

    @Override
    public boolean maySee(UUID memberId, String entityType, UUID entityId) {
        return effective.ownable(entityType)
                        .flatMap(ownable -> ownable.ownerOf(entityId))
                        .filter(memberId::equals)
                        .isPresent()
                || effective.levelOf(memberId, entityType, entityId).isPresent();
    }

    @Override
    public boolean mayWrite(
            UUID memberId, String entityType, UUID entityId, String containerType, UUID containerId) {
        Ownable ownable = effective.ownable(entityType).orElse(null);
        if (ownable == null) {
            return false;
        }

        var owner = ownable.ownerOf(entityId);
        if (owner.isPresent() && ownable.attachesToAnyType()) {
            // An existing comment belongs to whoever wrote it. Access to the carrier
            // lets everyone comment -- not rewrite what someone else said.
            return owner.get().equals(memberId);
        }
        if (owner.isPresent()) {
            // An existing item: the owner may do anything. Anyone else gets through this
            // gate at all from `CHECK` upwards -- which fields they may then actually
            // write is decided by `mayWriteField`. Requiring `WRITE` here already would
            // mean the `CHECK` level did not exist.
            return owner.get().equals(memberId)
                    || effective.levelOf(memberId, entityType, entityId)
                            .filter(level -> level.atLeast(AccessLevel.CHECK))
                            .isPresent();
        }

        if (ownable.idIsOwner() && !entityId.equals(memberId)) {
            // One per member, under the member's own id: nobody creates it for someone
            // else (a list order).
            return false;
        }
        // A new item. Without a container it belongs to whoever creates it; with a
        // container it needs `WRITE` on it -- otherwise anyone could create items in
        // every other person's list they may read.
        if (ownable.attachesToAnyType()) {
            // A comment: whoever may read the carrier may write on it. Without a carrier
            // it does not exist. The carrier is the item of that type: ids are unique per
            // table only, and an own list with the id of someone else's page opened the
            // page to comments from whoever made the list.
            return containerId != null && containerType != null && db.fetchExists(db.selectOne()
                    .from(EFFECTIVE_ACCESS)
                    .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(memberId))
                    .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(containerType))
                    .and(EFFECTIVE_ACCESS.ITEM_ID.eq(containerId)));
        }
        return mayPlaceIn(memberId, entityType, containerId);
    }

    @Override
    public boolean mayPlaceIn(UUID memberId, String entityType, UUID containerId) {
        if (containerId == null) {
            return true;
        }
        Ownable ownable = effective.ownable(entityType).orElse(null);
        String containerType = ownable == null ? null : ownable.containerType().orElse(null);
        if (containerType == null) {
            return true;
        }
        if (ownable.placedByContainerOwnerOnly()) {
            return effective.ownable(containerType)
                    .flatMap(container -> container.ownerOf(containerId))
                    .filter(memberId::equals)
                    .isPresent();
        }
        return effective.levelOf(memberId, containerType, containerId)
                .filter(level -> level.atLeast(ownable.placementLevel()))
                .isPresent();
    }

    @Override
    public boolean mayDelete(UUID memberId, String entityType, UUID entityId) {
        return access.mayDelete(memberId, entityType, entityId);
    }

    /**
     * An item that goes along with a delete: allowed if the member may delete it on its
     * own -- or if they own what is deleted and the item lies inside it. The owner of a
     * list takes every task in it along, whoever wrote it; a writer does not take along a
     * page they cannot see, and a subscription does not take along a calendar that is
     * someone else's.
     */
    @Override
    public boolean mayDeleteAlong(UUID memberId, String rootType, UUID rootId, String entityType, UUID entityId) {
        if (access.mayDelete(memberId, entityType, entityId)) {
            return true;
        }
        return access.ownerOf(rootType, rootId).filter(memberId::equals).isPresent()
                && access.inside(entityType, entityId, rootType, rootId);
    }

    /**
     * Whether this member may write this field.
     *
     * <p>The <em>check off</em> level allows exactly the status and nothing else — no
     * title, no date, no deleting. Without this distinction the level
     * could not be expressed, and the wall tablet could either do nothing or delete the
     * list.
     */
    @Override
    public boolean mayWriteField(UUID memberId, String entityType, UUID entityId, String field) {
        var ownable = effective.ownable(entityType);
        if (ownable.flatMap(candidate -> candidate.ownerOf(entityId)).filter(memberId::equals).isPresent()) {
            return true;
        }
        if (ownable.map(Ownable::ownerOnlyFields).orElse(java.util.Set.of()).contains(field)) {
            // Writing it would be sharing, and sharing is the owner's.
            return false;
        }
        AccessLevel level = effective.levelOf(memberId, entityType, entityId).orElse(null);
        if (level == null) {
            return false;
        }
        if (level.atLeast(AccessLevel.WRITE)) {
            return true;
        }
        return level == AccessLevel.CHECK && CHECKABLE_FIELDS.contains(field);
    }

    /**
     * The fields that <em>check off</em> covers.
     *
     * <p>They live here and not in the domain module because the level itself defines
     * them: "toggle a task's status, move a card to another column of a board and check
     * off occurrences of a series" — on a board the column is the progress, and moving a
     * card into the done column is ticking it off. If a module
     * came along with a check-off field of its own, it would belong here — and the list
     * would stay readable in one place.
     */
    private static final java.util.Set<String> CHECKABLE_FIELDS =
            java.util.Set.of("status", "columnId", "doneAt", "doneBy", "skipped", "occurrenceDate");

    /**
     * A just-written item gets its share immediately.
     *
     * <p>In the same transaction as the mutation: an event after the commit would be a
     * time window in which the owner could not see their own item.
     */
    @Override
    public void onEntityWritten(
            String entityType, UUID entityId, UUID actor, boolean created, java.util.Map<String, Object> chosen) {
        // Before the share is computed: it reads which assignees the owner chose.
        effective.ownable(entityType)
                .ifPresent(ownable -> ownable.assignmentWritten(entityId, chosenByOwner(ownable, entityId, actor, chosen)));
        if (created) {
            access.establish(entityType, entityId);
        } else {
            access.recalculate(entityType, entityId, actor);
        }
    }

    /**
     * The assignees the owner's own mutation added: those assigned now that the field did
     * not hold before. Nobody for a write by anyone else, for a write that leaves the field
     * alone -- ticking off, a new title -- and for a server write. Taking every current
     * assignee on any write of the owner made a writer's assignment the owner's as soon as
     * the owner, or the hourly refresh in the owner's name, touched the item.
     */
    private static java.util.List<UUID> chosenByOwner(
            Ownable ownable, UUID entityId, UUID actor, java.util.Map<String, Object> chosen) {
        String field = ownable.assigneeField().orElse(null);
        if (field == null
                || !chosen.containsKey(field)
                || ownable.ownerOf(entityId).filter(actor::equals).isEmpty()) {
            return java.util.List.of();
        }
        java.util.Set<UUID> before = new java.util.HashSet<>();
        if (chosen.get(field) instanceof java.util.Collection<?> values) {
            values.forEach(value -> before.add(UUID.fromString(value.toString())));
        }
        return ownable.assigneesOf(entityId).stream()
                .filter(subject -> !before.contains(subject))
                .toList();
    }
}
