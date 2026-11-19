package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.admin.Restorable;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.sync.ServerWrites;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The trash.
 *
 * <p>Forgotten in the design and mandatory nonetheless: <strong>without it every
 * disappearance is final, and for a family app that is the wrong promise</strong>.
 *
 * <p>It needs no table of its own — the retention period of the soft deletes <em>is</em>
 * the trash.
 */
@Service
class TrashService {

    private static final Logger log = LoggerFactory.getLogger(TrashService.class);

    private static final int DEFAULT_DAYS = 30;

    private final Map<String, Restorable> restorables;
    private final InstanceSettings settings;
    private final Access access;
    private final ServerWrites writes;

    TrashService(
            List<Restorable> restorables,
            InstanceSettings settings,
            Access access,
            ServerWrites writes) {
        this.restorables = restorables.stream().collect(Collectors.toMap(Restorable::itemType, Function.identity()));
        this.settings = settings;
        this.access = access;
        this.writes = writes;
    }

    record Entry(
            String itemType,
            UUID itemId,
            String title,
            String entityKey,
            Instant deletedAt,
            UUID deletedBy,
            int remainingDays,
            boolean restorable) {}

    int retentionDays() {
        return Math.max(1, settings.getInt(SettingKey.RETENTION_TRASH_DAYS, DEFAULT_DAYS));
    }

    /**
     * What this member sees in the trash.
     *
     * <p>Filtered like everything else: <strong>the administrator does not see other
     * people's content</strong>, not even in the trash. The share of a
     * deleted item is still there — it was not touched on delete.
     */
    @Transactional(readOnly = true)
    List<Entry> forMember(UUID memberId, String itemTypeFilter) {
        // Once, not per entry: the setting is a query of its own.
        int retention = retentionDays();
        Instant now = Instant.now();
        Instant notBefore = now.minus(Duration.ofDays(retention));
        List<Entry> entries = new ArrayList<>();

        for (Restorable restorable : restorables.values()) {
            if (itemTypeFilter != null && !itemTypeFilter.equals(restorable.itemType())) {
                continue;
            }
            List<Restorable.Deleted> deletedItems = restorable.deleted(notBefore);
            // Someone else's items in one question, not one per item.
            Set<UUID> writable = access.mayAll(
                    memberId,
                    restorable.itemType(),
                    deletedItems.stream()
                            .filter(deleted -> !memberId.equals(deleted.ownerId()))
                            .map(Restorable.Deleted::itemId)
                            .toList(),
                    AccessLevel.WRITE);
            for (Restorable.Deleted deleted : deletedItems) {
                boolean mine = memberId.equals(deleted.ownerId());
                // Writing on someone else's item is not enough: a list, a calendar or a
                // shared page comes back only by its owner's hand, as it went only by
                // theirs.
                if (!mine
                        && (!writable.contains(deleted.itemId())
                                || !access.mayDelete(memberId, restorable.itemType(), deleted.itemId()))) {
                    continue;
                }
                long remaining = Duration.between(now, deleted.deletedAt().plus(Duration.ofDays(retention)))
                        .toDays();
                entries.add(new Entry(
                        restorable.itemType(),
                        deleted.itemId(),
                        deleted.title(),
                        deleted.entityKey(),
                        deleted.deletedAt(),
                        deleted.deletedBy(),
                        (int) Math.max(0, remaining),
                        !deleted.containerGone()));
            }
        }
        entries.sort(Comparator.comparing(Entry::deletedAt).reversed());
        return entries;
    }

    /**
     * Brings an item back.
     *
     * <p>As a normal change in the log: the other devices learn about it the same way as
     * about any other change.
     *
     * @param targetContainerId where it goes instead of its old container, or {@code null}
     */
    @Transactional
    void restore(UUID memberId, String itemType, UUID itemId, UUID targetContainerId) {
        Restorable restorable = restorables.get(itemType);
        if (restorable == null) {
            throw HiwiskiException.invalid("trash.unknown_item_type", "itemType", itemType);
        }
        // The same filter as the listing: knowing an item's ID does not make it one's
        // own to undelete. Not found rather than forbidden -- a 403 would confirm that it
        // exists.
        UUID owner = restorable.deletedOwnerOf(itemId)
                .orElseThrow(() -> HiwiskiException.notFound("trash.item_not_found", "itemId", itemId));
        if (!memberId.equals(owner) && !access.mayDelete(memberId, itemType, itemId)) {
            throw HiwiskiException.notFound("trash.item_not_found", "itemId", itemId);
        }
        if (targetContainerId != null && !memberId.equals(owner)) {
            // Into another container is a move, and moving is the owner's.
            throw HiwiskiException.forbidden("access.denied");
        }
        if (targetContainerId == null && restorable.containerGone(itemId)) {
            // If its container is gone by now, it asks for a target.
            throw HiwiskiException.invalid("trash.container_gone", "itemId", itemId);
        }
        // Through sync, as a change with all fields: a device that pulled the delete has
        // nothing left of the item, and the search index dropped it too.
        writes.restore(itemType, itemId, targetContainerId, memberId);
    }

    /** Daily: delete for good what is older than the retention period. */
    @Scheduled(cron = "0 40 3 * * *")
    @Transactional
    public void purgeExpired() {
        Instant cutoff = Instant.now().minus(Duration.ofDays(retentionDays()));
        int removed = 0;
        for (Restorable restorable : restorables.values()) {
            removed += restorable.purgeOlderThan(cutoff);
        }
        if (removed > 0) {
            log.info("trash: purged {} items deleted more than {} days ago", removed, retentionDays());
        }
    }
}
