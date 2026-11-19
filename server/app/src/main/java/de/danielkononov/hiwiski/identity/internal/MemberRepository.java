package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.GROUP_MEMBER;
import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;
import static org.jooq.impl.DSL.multiset;
import static org.jooq.impl.DSL.select;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.jooq.Record12;
import org.jooq.Result;
import org.springframework.stereotype.Repository;

@Repository
class MemberRepository {

    private final DSLContext db;

    MemberRepository(DSLContext db) {
        this.db = db;
    }

    /**
     * The groups come along via {@code multiset} in the same query.
     *
     * <p>Without that, every member list needs a second round trip to the database per
     * row, and that is exactly the first thing you notice on the family overview.
     */
    private static org.jooq.Field<Result<org.jooq.Record1<UUID>>> groupIds() {
        return multiset(
                select(GROUP_MEMBER.GROUP_ID)
                        .from(GROUP_MEMBER)
                        .where(GROUP_MEMBER.MEMBER_ID.eq(MEMBER.ID)));
    }

    private static MemberRow toRow(Record12<UUID, String, String, String, Boolean, Boolean, String, String,
            OffsetDateTime, OffsetDateTime, UUID, Result<org.jooq.Record1<UUID>>> record) {
        return new MemberRow(
                record.value1(),
                record.value2(),
                record.value3(),
                record.value4(),
                record.value5(),
                record.value6(),
                record.value7(),
                record.value8(),
                record.value9(),
                record.value10(),
                record.value11(),
                record.value12().map(org.jooq.Record1::value1));
    }

    private org.jooq.SelectJoinStep<Record12<UUID, String, String, String, Boolean, Boolean, String, String,
            OffsetDateTime, OffsetDateTime, UUID, Result<org.jooq.Record1<UUID>>>> selectMembers() {
        return db.select(
                        MEMBER.ID,
                        MEMBER.USERNAME,
                        MEMBER.DISPLAY_NAME,
                        MEMBER.PASSWORD_HASH,
                        MEMBER.MUST_CHANGE_PASSWORD,
                        MEMBER.IS_ADMIN,
                        MEMBER.COLOR_TOKEN,
                        MEMBER.THEME_MODE,
                        MEMBER.CREATED_AT,
                        MEMBER.DISABLED_AT,
                        MEMBER.AVATAR_IMAGE_ID,
                        groupIds())
                .from(MEMBER);
    }

    Optional<MemberRow> find(UUID id) {
        return selectMembers().where(MEMBER.ID.eq(id)).fetchOptional(MemberRepository::toRow);
    }

    /** Via {@code lower(username)}, because that is how the index is defined. */
    Optional<MemberRow> findByUsername(String username) {
        return selectMembers()
                .where(DSL.lower(MEMBER.USERNAME).eq(username.trim().toLowerCase()))
                .fetchOptional(MemberRepository::toRow);
    }

    Optional<MemberRow> findAdministrator() {
        return selectMembers().where(MEMBER.IS_ADMIN.isTrue()).fetchOptional(MemberRepository::toRow);
    }

    List<MemberRow> all() {
        return selectMembers().orderBy(MEMBER.DISPLAY_NAME).fetch(MemberRepository::toRow);
    }

    boolean usernameTaken(String username) {
        return db.fetchExists(db.selectOne().from(MEMBER).where(DSL.lower(MEMBER.USERNAME).eq(username.trim().toLowerCase())));
    }

    void insert(
            UUID id,
            String username,
            String displayName,
            String passwordHash,
            boolean isAdmin,
            String colorToken) {
        db.insertInto(MEMBER)
                .set(MEMBER.ID, id)
                .set(MEMBER.USERNAME, username.trim().toLowerCase())
                .set(MEMBER.DISPLAY_NAME, displayName.trim())
                .set(MEMBER.PASSWORD_HASH, passwordHash)
                .set(MEMBER.IS_ADMIN, isAdmin)
                .set(MEMBER.COLOR_TOKEN, colorToken)
                .execute();
    }

    void updateProfile(UUID id, String displayName, String colorToken, String themeMode) {
        var update = db.update(MEMBER).set(MEMBER.ID, id);
        if (displayName != null) {
            update = update.set(MEMBER.DISPLAY_NAME, displayName.trim());
        }
        if (colorToken != null) {
            update = update.set(MEMBER.COLOR_TOKEN, colorToken);
        }
        if (themeMode != null) {
            update = update.set(MEMBER.THEME_MODE, themeMode);
        }
        update.where(MEMBER.ID.eq(id)).execute();
    }

    /** Whether the image was uploaded with this member as its carrier. */
    boolean isOwnPicture(UUID memberId, UUID imageId) {
        return db.fetchExists(MEDIA, MEDIA.ID.eq(imageId)
                .and(MEDIA.ITEM_TYPE.eq("MEMBER"))
                .and(MEDIA.ITEM_ID.eq(memberId)));
    }

    /** {@code null} takes the picture away — the initial shows again. */
    void setAvatar(UUID id, UUID imageId) {
        db.update(MEMBER).set(MEMBER.AVATAR_IMAGE_ID, imageId).where(MEMBER.ID.eq(id)).execute();
    }

    void updatePassword(UUID id, String passwordHash, boolean mustChange) {
        db.update(MEMBER)
                .set(MEMBER.PASSWORD_HASH, passwordHash)
                .set(MEMBER.MUST_CHANGE_PASSWORD, mustChange)
                .where(MEMBER.ID.eq(id))
                .execute();
    }

    void setDisabled(UUID id, boolean disabled) {
        db.update(MEMBER)
                .set(MEMBER.DISABLED_AT, disabled ? OffsetDateTime.now() : null)
                .where(MEMBER.ID.eq(id))
                .execute();
    }

    void setGroups(UUID memberId, List<UUID> groupIds) {
        db.deleteFrom(GROUP_MEMBER).where(GROUP_MEMBER.MEMBER_ID.eq(memberId)).execute();
        for (UUID groupId : groupIds) {
            db.insertInto(GROUP_MEMBER)
                    .set(GROUP_MEMBER.GROUP_ID, groupId)
                    .set(GROUP_MEMBER.MEMBER_ID, memberId)
                    .onConflictDoNothing()
                    .execute();
        }
    }

    List<UUID> groupsOf(UUID memberId) {
        return db.select(GROUP_MEMBER.GROUP_ID)
                .from(GROUP_MEMBER)
                .where(GROUP_MEMBER.MEMBER_ID.eq(memberId))
                .fetch(GROUP_MEMBER.GROUP_ID);
    }

    boolean any() {
        return db.fetchExists(db.selectOne().from(MEMBER));
    }
}
