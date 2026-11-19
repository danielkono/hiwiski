package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.INVITATION;

import java.time.OffsetDateTime;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Record;
import org.springframework.stereotype.Repository;

@Repository
class InvitationRepository {

    private final DSLContext db;

    InvitationRepository(DSLContext db) {
        this.db = db;
    }

    /** An invitation as stored: without its code, of which only the hash is kept. */
    record InvitationRow(
            UUID id,
            String displayName,
            List<UUID> groupIds,
            UUID createdBy,
            OffsetDateTime expiresAt,
            OffsetDateTime redeemedAt) {}

    private static InvitationRow toRow(Record record) {
        return new InvitationRow(
                record.get(INVITATION.ID),
                record.get(INVITATION.DISPLAY_NAME),
                Arrays.asList(record.get(INVITATION.GROUP_IDS)),
                record.get(INVITATION.CREATED_BY),
                record.get(INVITATION.EXPIRES_AT),
                record.get(INVITATION.REDEEMED_AT));
    }

    void insert(
            UUID id,
            String codeHash,
            String displayName,
            List<UUID> groupIds,
            UUID createdBy,
            OffsetDateTime expiresAt) {
        db.insertInto(INVITATION)
                .set(INVITATION.ID, id)
                .set(INVITATION.CODE_HASH, codeHash)
                .set(INVITATION.DISPLAY_NAME, displayName)
                .set(INVITATION.GROUP_IDS, groupIds.toArray(UUID[]::new))
                .set(INVITATION.CREATED_BY, createdBy)
                .set(INVITATION.EXPIRES_AT, expiresAt)
                .execute();
    }

    /** An open invitation with what is stored of its code, to check a code against. */
    record Candidate(InvitationRow invitation, String codeHash) {}

    /**
     * The invitations a code can open: not redeemed, not expired. An expired or used one
     * is not among them, so its code gets the same answer as a made-up one -- otherwise
     * the difference would reveal that it existed.
     */
    List<Candidate> valid() {
        return db.selectFrom(INVITATION)
                .where(INVITATION.REDEEMED_AT.isNull())
                .and(INVITATION.EXPIRES_AT.gt(OffsetDateTime.now()))
                .fetch(record -> new Candidate(toRow(record), record.get(INVITATION.CODE_HASH)));
    }

    Optional<InvitationRow> find(UUID id) {
        return db.selectFrom(INVITATION).where(INVITATION.ID.eq(id)).fetchOptional(InvitationRepository::toRow);
    }

    List<InvitationRow> open() {
        return db.selectFrom(INVITATION)
                .where(INVITATION.REDEEMED_AT.isNull())
                .and(INVITATION.EXPIRES_AT.gt(OffsetDateTime.now()))
                .orderBy(INVITATION.CREATED_AT.desc())
                .fetch(InvitationRepository::toRow);
    }

    /**
     * Redeem, but only once.
     *
     * <p>The condition {@code redeemed_at is null} is in the {@code UPDATE} and not in a
     * prior check: two devices redeeming the same code at the same time would otherwise
     * both get through.
     *
     * @return whether this call redeemed it
     */
    boolean redeem(UUID id, UUID memberId) {
        return db.update(INVITATION)
                        .set(INVITATION.REDEEMED_AT, OffsetDateTime.now())
                        .set(INVITATION.REDEEMED_MEMBER_ID, memberId)
                        .where(INVITATION.ID.eq(id))
                        .and(INVITATION.REDEEMED_AT.isNull())
                        .execute()
                == 1;
    }

    /**
     * Withdraw one nobody has redeemed.
     *
     * <p>The condition {@code redeemed_at is null} is in the {@code DELETE}, as it is in
     * {@link #redeem}'s {@code UPDATE}: of a withdrawal and a redemption at the same time
     * exactly one gets through, and a redeemed invitation stays the record of who joined
     * with it.
     *
     * @return whether this call withdrew it
     */
    boolean deleteUnredeemed(UUID id) {
        return db.deleteFrom(INVITATION)
                        .where(INVITATION.ID.eq(id))
                        .and(INVITATION.REDEEMED_AT.isNull())
                        .execute()
                == 1;
    }

    /** Invalidate expired ones -- hourly. */
    int deleteExpired() {
        return db.deleteFrom(INVITATION)
                .where(INVITATION.REDEEMED_AT.isNull())
                .and(INVITATION.EXPIRES_AT.lt(OffsetDateTime.now().minusDays(1)))
                .execute();
    }
}
