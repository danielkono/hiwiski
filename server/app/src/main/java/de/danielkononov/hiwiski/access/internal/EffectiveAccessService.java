package de.danielkononov.hiwiski.access.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.access.ItemRef;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.identity.Groups;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.jooq.DSLContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Resolves ownership, share, inheritance and assignment into {@code effective_access}.
 *
 * <p>Materialized, because with arbitrarily deep wiki pages the inheritance is a
 * recursive query and sits in <em>every</em> read query — including search and log
 * filtering. Recursive per query is not slow at family size, but it is the same logic in
 * fifteen places, and one of them gets forgotten.
 */
@Service
class EffectiveAccessService {

    /**
     * How deep an inheritance chain may go before it counts as a cycle.
     *
     * <p>Wiki pages nest arbitrarily deep. "Arbitrarily" is not very deep in
     * a family; this limit keeps a bent parent pointer from sending the server in
     * circles.
     */
    private static final int MAX_DEPTH = 64;

    private final DSLContext db;
    private final Map<String, Ownable> ownables;
    private final Groups groups;
    private final ShareRepository shares;
    private final de.danielkononov.hiwiski.identity.Members members;

    EffectiveAccessService(
            DSLContext db,
            List<Ownable> ownables,
            Groups groups,
            ShareRepository shares,
            de.danielkononov.hiwiski.identity.Members members) {
        this.db = db;
        this.ownables = ownables.stream().collect(Collectors.toMap(Ownable::itemType, Function.identity()));
        this.groups = groups;
        this.shares = shares;
        this.members = members;
    }

    Optional<Ownable> ownable(String itemType) {
        return Optional.ofNullable(ownables.get(itemType));
    }

    java.util.Collection<Ownable> ownables() {
        return ownables.values();
    }

    /** Every item assigned to this member or group, across all types. */
    List<ItemRef> assignedTo(UUID subject) {
        List<ItemRef> result = new ArrayList<>();
        ownables.values().forEach(ownable -> ownable.assignedTo(subject)
                .forEach(id -> result.add(new ItemRef(ownable.itemType(), id))));
        return result;
    }

    /** The types that live in this container type -- for the cascade. */
    private List<Ownable> childrenOf(String containerType) {
        return ownables.values().stream()
                .filter(candidate -> candidate.attachesToAnyType()
                        || candidate.containerType().filter(containerType::equals).isPresent())
                .toList();
    }

    /**
     * Recomputes and reports what changed in the process.
     *
     * <p>The result is not a by-product: it carries the synthetic log entries. Without
     * them, someone newly granted access would never get the history, because it lies
     * <em>before</em> their state.
     */
    @Transactional
    Changed recalculate(String itemType, UUID itemId) {
        List<ItemChange> changes = new ArrayList<>();
        recalculate(itemType, itemId, 0, changes);
        return new Changed(changes);
    }

    private void recalculate(String itemType, UUID itemId, int depth, List<ItemChange> changes) {
        if (depth > MAX_DEPTH) {
            return;
        }
        Ownable ownable = ownables.get(itemType);
        if (ownable == null) {
            return;
        }

        changes.add(write(itemType, itemId, resolve(ownable, itemId, 0)));

        // The cascade: when a list's share changes, it changes for every task in it --
        // and further down.
        for (Ownable child : childrenOf(itemType)) {
            // Deleted ones too: their rows decide the trash, and a revived one would
            // otherwise come back with the access of before.
            for (UUID childId : child.allInContainer(itemId)) {
                recalculate(child.itemType(), childId, depth + 1, changes);
            }
        }
    }

    private record Grant(AccessLevel level, Access.GrantSource source) {}

    /**
     * The resolution for one item.
     *
     * <p>Order: owner, then the direct share — or, if there is none, the inherited one —,
     * then the assignment. The higher level wins, so that nobody may do <em>less</em>
     * because of an additional row.
     */
    private Map<UUID, Grant> resolve(Ownable ownable, UUID itemId, int depth) {
        Map<UUID, Grant> result = audience(ownable, itemId, depth);

        // Assigning shares automatically. It cannot be removed on its own -- it
        // disappears with the assignment. But only an assignment the
        // owner made shares: one by someone who may merely write raises the level of
        // whoever sees the item already, and brings nobody new in -- otherwise *write*
        // could share, and assigning oneself would outlive a revoked share.
        List<UUID> assignees = ownable.assigneesOf(itemId);
        if (!assignees.isEmpty()) {
            List<UUID> byOwner = ownable.ownerAssigneesOf(itemId);
            Set<UUID> audience = new HashSet<>(result.keySet());
            expandSubjects(byOwner, ownable.assignmentLevel())
                    .forEach((member, level) ->
                            merge(result, member, new Grant(level, Access.GrantSource.ASSIGNED)));
            expandSubjects(
                            assignees.stream().filter(subject -> !byOwner.contains(subject)).toList(),
                            ownable.assignmentLevel())
                    .forEach((member, level) -> {
                        if (audience.contains(member)) {
                            merge(result, member, new Grant(level, Access.GrantSource.ASSIGNED));
                        }
                    });
        }

        return result;
    }

    /** Who sees the item without its assignment: the owner, and its own or inherited share. */
    private Map<UUID, Grant> audience(Ownable ownable, UUID itemId, int depth) {
        Map<UUID, Grant> result = new LinkedHashMap<>();

        ownable.ownerOf(itemId)
                .ifPresent(owner -> result.put(owner, new Grant(AccessLevel.WRITE, Access.GrantSource.OWNER)));

        List<ShareRepository.ShareRow> own = shares.of(ownable.itemType(), itemId);
        if (!own.isEmpty()) {
            expand(own).forEach((member, level) ->
                    merge(result, member, new Grant(level, Access.GrantSource.DIRECT)));
        } else {
            // No direct share: the container's applies, namely its resolved one -- that
            // way it reaches through arbitrarily deep.
            inherited(ownable, itemId, depth)
                    .forEach((member, level) ->
                            merge(result, member, new Grant(level, Access.GrantSource.INHERITED)));
        }
        return result;
    }

    private Map<UUID, AccessLevel> inherited(Ownable ownable, UUID itemId, int depth) {
        if (depth > MAX_DEPTH) {
            return Map.of();
        }
        Optional<ItemRef> container = ownable.containerOf(itemId);
        if (container.isEmpty()) {
            return Map.of();
        }
        Ownable parent = ownables.get(container.get().itemType());
        if (parent == null) {
            return Map.of();
        }
        Map<UUID, AccessLevel> result = new LinkedHashMap<>();
        // Without the container's owner: whoever owns a list sees its tasks anyway -- but
        // as owner of the list, not of the task. The row in the sheet says "inherited
        // from the list", and then that is actually true.
        resolve(parent, container.get().itemId(), depth + 1)
                .forEach((member, grant) -> result.put(member, grant.level()));
        return result;
    }

    /** Groups are resolved here — on write, not when the share is stored. */
    private Map<UUID, AccessLevel> expand(List<ShareRepository.ShareRow> rows) {
        Map<UUID, AccessLevel> result = new LinkedHashMap<>();
        for (ShareRepository.ShareRow row : rows) {
            if (row.subjectType() == Access.SubjectType.MEMBER) {
                merge(result, row.subjectId(), row.level());
            } else {
                for (UUID member : groups.membersOf(row.subjectId())) {
                    merge(result, member, row.level());
                }
            }
        }
        return result;
    }

    /** Assignments name members <em>and</em> groups without distinguishing them. */
    private Map<UUID, AccessLevel> expandSubjects(List<UUID> subjects, AccessLevel level) {
        Map<UUID, AccessLevel> result = new LinkedHashMap<>();
        for (UUID subject : subjects) {
            // A group by being one, not by having members: an empty group was taken for
            // a member, its ID went into `effective_access.member_id`, and the foreign
            // key failed the whole mutation with a 500.
            if (groups.find(subject).isPresent()) {
                groups.membersOf(subject).forEach(member -> merge(result, member, level));
            } else if (members.find(subject).isPresent()) {
                merge(result, subject, level);
            }
            // Neither: a group deleted since it was assigned. It reaches nobody.
        }
        return result;
    }

    private static void merge(Map<UUID, AccessLevel> target, UUID member, AccessLevel level) {
        target.merge(member, level, (a, b) -> a.atLeast(b) ? a : b);
    }

    private static void merge(Map<UUID, Grant> target, UUID member, Grant grant) {
        target.merge(member, grant, (a, b) -> a.level().atLeast(b.level()) ? a : b);
    }

    /**
     * Writes the result and reports who was added and who dropped out.
     *
     * <p>The two sets carry the synthetic log entries: without them, someone newly
     * granted access would never get the history, because it lies <em>before</em> their
     * state.
     */
    private ItemChange write(String itemType, UUID itemId, Map<UUID, Grant> resolved) {
        Map<UUID, Grant> before = new HashMap<>();
        db.select(EFFECTIVE_ACCESS.MEMBER_ID, EFFECTIVE_ACCESS.LEVEL, EFFECTIVE_ACCESS.SOURCE)
                .from(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.ITEM_TYPE.eq(itemType))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(itemId))
                .forEach(row -> before.put(
                        row.value1(),
                        new Grant(AccessLevel.valueOf(row.value2()), Access.GrantSource.valueOf(row.value3()))));

        // Only what changed is written. Deleting and inserting every row each time made a
        // server start — which recomputes everything shared with a group — rewrite the
        // whole table, and every recomputation rewrite rows that stayed the same.
        List<UUID> stale = before.entrySet().stream()
                .filter(entry -> !entry.getValue().equals(resolved.get(entry.getKey())))
                .map(Map.Entry::getKey)
                .toList();
        if (!stale.isEmpty()) {
            db.deleteFrom(EFFECTIVE_ACCESS)
                    .where(EFFECTIVE_ACCESS.ITEM_TYPE.eq(itemType))
                    .and(EFFECTIVE_ACCESS.ITEM_ID.eq(itemId))
                    .and(EFFECTIVE_ACCESS.MEMBER_ID.in(stale))
                    .execute();
        }
        var fresh = resolved.entrySet().stream()
                .filter(entry -> !entry.getValue().equals(before.get(entry.getKey())))
                .toList();
        if (!fresh.isEmpty()) {
            var insert = db.insertInto(
                    EFFECTIVE_ACCESS,
                    EFFECTIVE_ACCESS.MEMBER_ID,
                    EFFECTIVE_ACCESS.ITEM_TYPE,
                    EFFECTIVE_ACCESS.ITEM_ID,
                    EFFECTIVE_ACCESS.LEVEL,
                    EFFECTIVE_ACCESS.SOURCE);
            for (var entry : fresh) {
                insert = insert.values(
                        entry.getKey(),
                        itemType,
                        itemId,
                        entry.getValue().level().name(),
                        entry.getValue().source().name());
            }
            insert.onConflictDoNothing().execute();
        }

        List<UUID> granted = resolved.keySet().stream().filter(member -> !before.containsKey(member)).toList();
        List<UUID> revoked = before.keySet().stream().filter(member -> !resolved.containsKey(member)).toList();
        return new ItemChange(itemType, itemId, granted, revoked);
    }

    /** Who was added to an item and who dropped out. */
    record ItemChange(String itemType, UUID itemId, List<UUID> granted, List<UUID> revoked) {}

    /** The same for a whole subtree. */
    record Changed(List<ItemChange> items) {

        boolean isEmpty() {
            return items.stream().allMatch(item -> item.granted().isEmpty() && item.revoked().isEmpty());
        }
    }

    @Transactional(readOnly = true)
    /** The member's level on each of these items that they have one on — one query. */
    Map<UUID, AccessLevel> levelsOf(UUID memberId, String itemType, java.util.Collection<UUID> itemIds) {
        if (itemIds.isEmpty()) {
            return Map.of();
        }
        return db.select(EFFECTIVE_ACCESS.ITEM_ID, EFFECTIVE_ACCESS.LEVEL)
                .from(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(memberId))
                .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(itemType))
                .and(EFFECTIVE_ACCESS.ITEM_ID.in(itemIds))
                .fetchMap(EFFECTIVE_ACCESS.ITEM_ID, row -> AccessLevel.parse(row.value2()));
    }

    Optional<AccessLevel> levelOf(UUID memberId, String itemType, UUID itemId) {
        return Optional.ofNullable(db.select(EFFECTIVE_ACCESS.LEVEL)
                        .from(EFFECTIVE_ACCESS)
                        .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(memberId))
                        .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(itemType))
                        .and(EFFECTIVE_ACCESS.ITEM_ID.eq(itemId))
                        .fetchOne(EFFECTIVE_ACCESS.LEVEL))
                .map(AccessLevel::parse);
    }

    /**
     * The rows of the sheet, in the order it shows them: owner,
     * automatically assigned, inherited, direct.
     *
     * <p>Inherited ones come out as recipients the way they are on the container — as a
     * group if a group is there. Resolving them into members would be wrong here: the
     * sheet should show what someone set, not what follows from it.
     */
    @Transactional(readOnly = true)
    List<Access.Grant> grantsOn(String itemType, UUID itemId) {
        List<Access.Grant> result = new ArrayList<>();
        Ownable ownable = ownables.get(itemType);
        if (ownable == null) {
            return result;
        }

        // 1. Owner, not changeable.
        ownable.ownerOf(itemId)
                .ifPresent(owner -> result.add(new Access.Grant(
                        Access.SubjectType.MEMBER, owner, AccessLevel.WRITE, Access.GrantSource.OWNER, null)));

        // 2. Automatically assigned, with a note. They cannot be removed on their own --
        //    they disappear with the assignment. Only those the assignment shares with:
        //    whom the owner assigned, and whom someone else assigned only if they see the
        //    item anyway (all of a group). The sheet said "automatic · assigned" for
        //    someone who saw nothing (the sheet shows who sees the item).
        List<UUID> byOwner = ownable.ownerAssigneesOf(itemId);
        Set<UUID> audience = audience(ownable, itemId, 0).keySet();
        for (UUID subject : ownable.assigneesOf(itemId)) {
            List<UUID> members = groups.find(subject).isPresent() ? groups.membersOf(subject) : List.of(subject);
            if (!byOwner.contains(subject) && (members.isEmpty() || !audience.containsAll(members))) {
                continue;
            }
            boolean isGroup = !groups.membersOf(subject).isEmpty();
            result.add(new Access.Grant(
                    isGroup ? Access.SubjectType.GROUP : Access.SubjectType.MEMBER,
                    subject,
                    ownable.assignmentLevel(),
                    Access.GrantSource.ASSIGNED,
                    null));
        }

        List<ShareRepository.ShareRow> own = shares.of(itemType, itemId);
        if (own.isEmpty()) {
            // 3. Inherited, grayed out, with origin.
            ownable.containerOf(itemId).ifPresent(container -> {
                for (ShareRepository.ShareRow row : inheritedShares(container.itemType(), container.itemId(), 0)) {
                    result.add(new Access.Grant(
                            row.subjectType(),
                            row.subjectId(),
                            row.level(),
                            Access.GrantSource.INHERITED,
                            container.itemType()));
                }
            });
        } else {
            // 4. Direct, each with a level picker.
            for (ShareRepository.ShareRow row : own) {
                result.add(new Access.Grant(
                        row.subjectType(), row.subjectId(), row.level(), Access.GrantSource.DIRECT, null));
            }
        }
        return result;
    }

    /** The nearest share set above -- the chain continues until one is found. */
    private List<ShareRepository.ShareRow> inheritedShares(String itemType, UUID itemId, int depth) {
        if (depth > MAX_DEPTH) {
            return List.of();
        }
        List<ShareRepository.ShareRow> own = shares.of(itemType, itemId);
        if (!own.isEmpty()) {
            return own;
        }
        Ownable ownable = ownables.get(itemType);
        if (ownable == null) {
            return List.of();
        }
        return ownable.containerOf(itemId)
                .map(container -> inheritedShares(container.itemType(), container.itemId(), depth + 1))
                .orElse(List.of());
    }

    /** Whether this item has a direct share -- otherwise the sheet shows "inherited". */
    @Transactional(readOnly = true)
    Optional<de.danielkononov.hiwiski.access.ItemRef> inheritsFrom(String itemType, UUID itemId) {
        if (shares.anyFor(itemType, itemId)) {
            return Optional.empty();
        }
        Ownable ownable = ownables.get(itemType);
        return ownable == null ? Optional.empty() : ownable.containerOf(itemId);
    }
}
