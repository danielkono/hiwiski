package de.danielkononov.hiwiski.access.internal;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.access.ItemRef;
import de.danielkononov.hiwiski.access.Ownable;
import de.danielkononov.hiwiski.identity.GroupDeleted;
import de.danielkononov.hiwiski.identity.GroupMembersChanged;
import de.danielkononov.hiwiski.identity.GroupInfo;
import de.danielkononov.hiwiski.identity.Groups;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.SyntheticChanges;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Reading and writing shares, and getting their consequences into the log. */
@Service
class AccessService implements Access {

    private final ShareRepository shares;
    private final EffectiveAccessService effective;
    private final SyntheticChanges synthetic;
    private final ChangeSequence sequence;
    private final Groups groups;

    AccessService(
            ShareRepository shares,
            EffectiveAccessService effective,
            SyntheticChanges synthetic,
            ChangeSequence sequence,
            Groups groups) {
        this.shares = shares;
        this.effective = effective;
        this.synthetic = synthetic;
        this.sequence = sequence;
        this.groups = groups;
    }

    @Override
    public Optional<AccessLevel> levelOf(UUID memberId, String itemType, UUID itemId) {
        return effective.levelOf(memberId, itemType, itemId);
    }

    @Override
    @Transactional
    public void recalculate(String itemType, UUID itemId, UUID cause) {
        announce(effective.recalculate(itemType, itemId), cause);
    }

    @Override
    public java.util.Set<UUID> mayAll(
            UUID memberId, String itemType, java.util.Collection<UUID> itemIds, AccessLevel required) {
        return effective.levelsOf(memberId, itemType, itemIds).entrySet().stream()
                .filter(entry -> entry.getValue().atLeast(required))
                .map(Map.Entry::getKey)
                .collect(java.util.stream.Collectors.toSet());
    }

    @Override
    public boolean mayDelete(UUID memberId, String itemType, UUID itemId) {
        Ownable ownable = effective.ownable(itemType).orElse(null);
        if (ownable == null) {
            return false;
        }
        var owner = ownable.ownerOf(itemId);
        if (owner.isEmpty() || owner.get().equals(memberId)) {
            // Gone already, or one's own: an absent item is a delete that has arrived.
            return true;
        }
        if (ownable.attachesToAnyType()) {
            // Someone else's comment stays, whatever the access to the carrier.
            return false;
        }
        // Within the container, not the container: whoever was given a list, a calendar
        // or a branch of pages to write in was not given it to throw away, with
        // everything in it that others put there.
        var container = ownable.containerOf(itemId).orElse(null);
        if (container == null) {
            return false;
        }
        // Write, or what placing one there takes: unticking an occurrence of a series is
        // deleting it, and *check off* may.
        AccessLevel required = ownable.placementLevel();
        return may(memberId, itemType, itemId, required)
                && may(memberId, container.itemType(), container.itemId(), required);
    }

    /**
     * Whether {@code itemId} lies inside {@code containerId}, at any depth -- a task in a
     * list, a subpage below a page.
     */
    boolean inside(String itemType, UUID itemId, String containerType, UUID containerId) {
        String type = itemType;
        UUID id = itemId;
        for (int depth = 0; depth < 64; depth++) {
            var ownable = effective.ownable(type).orElse(null);
            if (ownable == null) {
                return false;
            }
            var container = ownable.containerOf(id).orElse(null);
            if (container == null) {
                return false;
            }
            if (container.itemType().equals(containerType) && container.itemId().equals(containerId)) {
                return true;
            }
            type = container.itemType();
            id = container.itemId();
        }
        return false;
    }

    /** The owner of an item, deleted or not. */
    Optional<UUID> ownerOf(String itemType, UUID itemId) {
        return effective.ownable(itemType).flatMap(ownable -> ownable.ownerOf(itemId));
    }

    @Override
    @Transactional
    public void establish(String itemType, UUID itemId) {
        effective.recalculate(itemType, itemId);
    }

    @Override
    public List<Grant> grantsOn(String itemType, UUID itemId) {
        return effective.grantsOn(itemType, itemId);
    }

    /**
     * Sets an item's direct shares.
     *
     * <p>Only the owner may do that: <em>write</em> allows creating, changing and deleting
     * within the container — <strong>not</strong> changing the share.
     */
    @Transactional
    void replace(String itemType, UUID itemId, List<ShareRepository.ShareRow> rows, UUID actor) {
        Ownable ownable = effective.ownable(itemType)
                .orElseThrow(() -> HiwiskiException.invalid("access.unknown_item_type", "itemType", itemType));
        UUID owner = ownable.ownerOf(itemId)
                .orElseThrow(() -> HiwiskiException.notFound("access.item_not_found", "itemId", itemId));
        if (!owner.equals(actor)) {
            // 404 and not 403 for whoever may not see it: the difference told them that
            // an id they made up exists.
            if (levelOf(actor, itemType, itemId).isEmpty()) {
                throw HiwiskiException.notFound("access.item_not_found", "itemId", itemId);
            }
            throw HiwiskiException.forbidden("access.only_owner_may_share");
        }
        if (!ownable.shareable()) {
            // A board, its tiles, a feed, a list order: one member's own.
            throw HiwiskiException.invalid("access.not_shareable", "itemType", itemType);
        }
        if (!ownable.checkable() && rows.stream().anyMatch(row -> row.level() == AccessLevel.CHECK)) {
            throw HiwiskiException.invalid("access.check_not_applicable", "itemType", itemType);
        }
        shares.replace(itemType, itemId, rows, actor);
        recalculate(itemType, itemId, actor);
    }

    /**
     * Someone joined or left a group: everything shared with or assigned to the group is
     * computed again.
     *
     * <p>Synchronous, in the transaction that changed the membership — the visibility has
     * to be right when it commits, like on every write. Whoever joins gets
     * {@code access_granted} and with it the history; whoever leaves gets
     * {@code access_revoked}. No cause is skipped: the person who edited the group is not
     * the one who gained or lost something.
     */
    @EventListener
    @Transactional
    void onGroupMembersChanged(GroupMembersChanged event) {
        var items = new LinkedHashSet<ItemRef>();
        for (UUID group : event.groupIds()) {
            items.addAll(shares.itemsFor(SubjectType.GROUP, group));
            items.addAll(effective.assignedTo(group));
        }
        items.forEach(item -> recalculate(item.itemType(), item.itemId(), null));
    }

    /** A deleted group's shares go, and every item it reached is computed again. */
    @EventListener
    @Transactional
    void onGroupDeleted(GroupDeleted event) {
        var items = new LinkedHashSet<ItemRef>();
        items.addAll(shares.itemsFor(SubjectType.GROUP, event.groupId()));
        items.addAll(effective.assignedTo(event.groupId()));
        shares.removeSubject(SubjectType.GROUP, event.groupId());
        items.forEach(item -> recalculate(item.itemType(), item.itemId(), null));
    }

    /**
     * Once at start: every group computed again.
     *
     * <p>Until group membership changes triggered a recomputation, a member who joined a
     * group later never got what had been shared with it. This repairs instances from
     * that time. Idempotent — it writes log entries only where the access actually
     * changes, so every start after the first finds nothing to do.
     */
    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    void reconcileGroups() {
        onGroupMembersChanged(new GroupMembersChanged(groups.all().stream().map(GroupInfo::id).toList()));
    }

    /**
     * Once at start: shares on types that cannot be shared go.
     *
     * <p>Until the server refused them, a board could be shared through the API, and
     * whoever it was shared with read its token -- a session of its owner -- through sync.
     * Idempotent: after the first start there is nothing left to remove.
     */
    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    void dropUnshareable() {
        for (Ownable ownable : effective.ownables()) {
            if (ownable.shareable()) {
                continue;
            }
            for (UUID itemId : shares.itemsOfType(ownable.itemType())) {
                shares.replace(ownable.itemType(), itemId, List.of(), null);
                recalculate(ownable.itemType(), itemId, null);
            }
        }
    }

    /**
     * Writes the synthetic log entries.
     *
     * <p>Sync runs on a sequence number. If someone gets access today to a list that was
     * filled last month, those changes lie <em>before</em> their state — they would never
     * get them. Hence {@code access_granted}, on which the client pulls the container
     * again in full, and {@code access_revoked}, on which it deletes the local data.
     */
    private void announce(EffectiveAccessService.Changed changed, UUID cause) {
        if (changed.isEmpty()) {
            return;
        }
        for (var item : changed.items()) {
            for (UUID member : item.granted()) {
                if (member.equals(cause)) {
                    continue;
                }
                synthetic.append(sequence.next(), "access_granted", item.itemType(), item.itemId(), member);
            }
            for (UUID member : item.revoked()) {
                if (member.equals(cause)) {
                    continue;
                }
                synthetic.append(sequence.next(), "access_revoked", item.itemType(), item.itemId(), member);
            }
        }
    }
}
