package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.DEVICE;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.Record;
import org.jooq.impl.DSL;
import org.springframework.stereotype.Repository;

@Repository
class DeviceRepository {

    private final DSLContext db;

    DeviceRepository(DSLContext db) {
        this.db = db;
    }

    record DeviceRow(
            UUID id,
            UUID memberId,
            String name,
            String platform,
            OffsetDateTime createdAt,
            OffsetDateTime lastSeenAt,
            long lastSyncSeq,
            int pendingCount,
            boolean staySignedIn) {}

    /** A session without "Stay signed in" ends this long after the device was last seen. */
    static final Duration SESSION_IDLE = Duration.ofHours(12);

    /** Any device ends this long after it was last seen. */
    static final Duration DEVICE_IDLE = Duration.ofDays(180);

    private static DeviceRow toRow(Record record) {
        return new DeviceRow(
                record.get(DEVICE.ID),
                record.get(DEVICE.MEMBER_ID),
                record.get(DEVICE.NAME),
                record.get(DEVICE.PLATFORM),
                record.get(DEVICE.CREATED_AT),
                record.get(DEVICE.LAST_SEEN_AT),
                record.get(DEVICE.LAST_SYNC_SEQ),
                record.get(DEVICE.PENDING_COUNT),
                record.get(DEVICE.STAY_SIGNED_IN));
    }

    /** When the device was last seen -- or registered, if never since. */
    private static org.jooq.Field<OffsetDateTime> lastActive() {
        return DSL.coalesce(DEVICE.LAST_SEEN_AT, DEVICE.CREATED_AT);
    }

    /** Ended on its own: a session idle too long, or any device idle for half a year. */
    private static Condition expired(OffsetDateTime now) {
        return DEVICE.STAY_SIGNED_IN
                .isFalse()
                .and(lastActive().lt(now.minus(SESSION_IDLE)))
                .or(lastActive().lt(now.minus(DEVICE_IDLE)));
    }

    void insert(
            UUID id,
            UUID memberId,
            String name,
            String platform,
            String tokenHash,
            boolean staySignedIn,
            UUID installationId) {
        db.insertInto(DEVICE)
                .set(DEVICE.ID, id)
                .set(DEVICE.MEMBER_ID, memberId)
                .set(DEVICE.NAME, name)
                .set(DEVICE.PLATFORM, platform)
                .set(DEVICE.TOKEN_HASH, tokenHash)
                .set(DEVICE.STAY_SIGNED_IN, staySignedIn)
                .set(DEVICE.INSTALLATION_ID, installationId)
                .execute();
    }

    /**
     * Retires the devices an installation registered before for the same member: the
     * app holds one token at a time, so the earlier ones are dead even when their
     * sign-out never arrived. Returns their ids.
     *
     * <p>Only the member's own. The installation id comes from the client and proves
     * nothing; retiring every member's devices with it let anyone who learned another
     * device's id sign that device out by signing in themselves. Another member's
     * entry from the same installation ends on its own (idle expiry) instead.
     */
    List<UUID> retireInstallation(UUID installationId, UUID memberId) {
        return db.update(DEVICE)
                .set(DEVICE.REVOKED_AT, OffsetDateTime.now())
                .where(DEVICE.INSTALLATION_ID.eq(installationId))
                .and(DEVICE.MEMBER_ID.eq(memberId))
                .and(DEVICE.REVOKED_AT.isNull())
                .returning(DEVICE.ID)
                .fetch(DEVICE.ID);
    }

    /**
     * Whether this installation ever signed in to this member's account -- for the
     * sign-in ceiling (LoginThrottle), which lets it through. Revoked devices count: a
     * member whose devices an administrator's reset signed out signs in again on the
     * same phone.
     */
    boolean installationKnown(UUID installationId, UUID memberId) {
        return db.fetchExists(db.selectOne()
                .from(DEVICE)
                .where(DEVICE.INSTALLATION_ID.eq(installationId))
                .and(DEVICE.MEMBER_ID.eq(memberId)));
    }

    /** Revokes the devices that ended on their own; returns their ids. */
    List<UUID> revokeExpired() {
        return db.update(DEVICE)
                .set(DEVICE.REVOKED_AT, OffsetDateTime.now())
                .where(DEVICE.REVOKED_AT.isNull())
                .and(expired(OffsetDateTime.now()))
                .returning(DEVICE.ID)
                .fetch(DEVICE.ID);
    }

    /**
     * The lookup path on authentication: the token is stored here only as a hash.
     *
     * <p>Revoked devices drop out -- a revocation takes effect immediately, not only at
     * the next expiry -- and so do expired ones. That is exactly why there is no JWT.
     */
    Optional<DeviceRow> findByTokenHash(String tokenHash) {
        return db.select(
                        DEVICE.ID,
                        DEVICE.MEMBER_ID,
                        DEVICE.NAME,
                        DEVICE.PLATFORM,
                        DEVICE.CREATED_AT,
                        DEVICE.LAST_SEEN_AT,
                        DEVICE.LAST_SYNC_SEQ,
                        DEVICE.PENDING_COUNT,
                        DEVICE.STAY_SIGNED_IN)
                .from(DEVICE)
                .where(DEVICE.TOKEN_HASH.eq(tokenHash))
                .and(DEVICE.REVOKED_AT.isNull())
                // Ended on its own counts at once, not only once the cleanup ran.
                .and(DSL.not(expired(OffsetDateTime.now())))
                .fetchOptional(DeviceRepository::toRow);
    }

    List<DeviceRow> ofMember(UUID memberId) {
        return db.select(
                        DEVICE.ID,
                        DEVICE.MEMBER_ID,
                        DEVICE.NAME,
                        DEVICE.PLATFORM,
                        DEVICE.CREATED_AT,
                        DEVICE.LAST_SEEN_AT,
                        DEVICE.LAST_SYNC_SEQ,
                        DEVICE.PENDING_COUNT,
                        DEVICE.STAY_SIGNED_IN)
                .from(DEVICE)
                .where(DEVICE.MEMBER_ID.eq(memberId))
                .and(DEVICE.REVOKED_AT.isNull())
                .and(DSL.not(expired(OffsetDateTime.now())))
                .orderBy(DEVICE.CREATED_AT)
                .fetch(DeviceRepository::toRow);
    }

    /**
     * Revokes every device of the member except {@code keep} (none when {@code null});
     * returns their ids.
     */
    List<UUID> revokeAllOf(UUID memberId, UUID keep) {
        Condition others = keep == null ? DSL.noCondition() : DEVICE.ID.ne(keep);
        return db.update(DEVICE)
                .set(DEVICE.REVOKED_AT, OffsetDateTime.now())
                .where(DEVICE.MEMBER_ID.eq(memberId))
                .and(DEVICE.REVOKED_AT.isNull())
                .and(others)
                .returning(DEVICE.ID)
                .fetch(DEVICE.ID);
    }

    /** Takes effect immediately: the filter no longer finds the device on the next call. */
    int revoke(UUID id, UUID memberId) {
        return db.update(DEVICE)
                .set(DEVICE.REVOKED_AT, OffsetDateTime.now())
                .where(DEVICE.ID.eq(id))
                .and(DEVICE.MEMBER_ID.eq(memberId))
                .and(DEVICE.REVOKED_AT.isNull())
                .execute();
    }

    /**
     * Recorded on every call.
     *
     * <p>Deliberately without a transaction of its own and without feedback: a failed
     * timestamp must not cost a request.
     */
    void touch(UUID id) {
        db.update(DEVICE)
                .set(DEVICE.LAST_SEEN_AT, OffsetDateTime.now())
                .where(DEVICE.ID.eq(id))
                .execute();
    }
}
