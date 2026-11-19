package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.GROUP;
import static de.danielkononov.hiwiski.db.generated.Tables.GROUP_MEMBER;
import static org.jooq.impl.DSL.multiset;
import static org.jooq.impl.DSL.select;

import de.danielkononov.hiwiski.identity.GroupInfo;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Record1;
import org.jooq.Record5;
import org.jooq.Result;
import org.springframework.stereotype.Repository;

@Repository
class GroupRepository {

    private final DSLContext db;

    GroupRepository(DSLContext db) {
        this.db = db;
    }

    private static GroupInfo toInfo(
            Record5<UUID, String, String, Integer, Result<Record1<UUID>>> record) {
        return new GroupInfo(
                record.value1(),
                record.value2(),
                record.value3(),
                record.value4(),
                record.value5().map(Record1::value1));
    }

    private org.jooq.SelectJoinStep<Record5<UUID, String, String, Integer, Result<Record1<UUID>>>> selectGroups() {
        return db.select(
                        GROUP.ID,
                        GROUP.NAME,
                        GROUP.ICON_TOKEN,
                        GROUP.POSITION,
                        multiset(
                                select(GROUP_MEMBER.MEMBER_ID)
                                        .from(GROUP_MEMBER)
                                        .where(GROUP_MEMBER.GROUP_ID.eq(GROUP.ID))))
                .from(GROUP);
    }

    Optional<GroupInfo> find(UUID id) {
        return selectGroups().where(GROUP.ID.eq(id)).fetchOptional(GroupRepository::toInfo);
    }

    List<GroupInfo> all() {
        return selectGroups().orderBy(GROUP.POSITION, GROUP.NAME).fetch(GroupRepository::toInfo);
    }

    List<UUID> membersOf(UUID groupId) {
        return db.select(GROUP_MEMBER.MEMBER_ID)
                .from(GROUP_MEMBER)
                .where(GROUP_MEMBER.GROUP_ID.eq(groupId))
                .fetch(GROUP_MEMBER.MEMBER_ID);
    }

    UUID insert(UUID id, String name, String iconToken, int position) {
        db.insertInto(GROUP)
                .set(GROUP.ID, id)
                .set(GROUP.NAME, name.trim())
                .set(GROUP.ICON_TOKEN, iconToken)
                .set(GROUP.POSITION, position)
                .execute();
        return id;
    }

    void update(UUID id, String name, String iconToken) {
        db.update(GROUP)
                .set(GROUP.NAME, name.trim())
                .set(GROUP.ICON_TOKEN, iconToken)
                .where(GROUP.ID.eq(id))
                .execute();
    }

    void setMembers(UUID groupId, List<UUID> memberIds) {
        db.deleteFrom(GROUP_MEMBER).where(GROUP_MEMBER.GROUP_ID.eq(groupId)).execute();
        for (UUID memberId : memberIds) {
            db.insertInto(GROUP_MEMBER)
                    .set(GROUP_MEMBER.GROUP_ID, groupId)
                    .set(GROUP_MEMBER.MEMBER_ID, memberId)
                    .onConflictDoNothing()
                    .execute();
        }
    }

    /** The memberships go along via {@code on delete cascade}. */
    void delete(UUID id) {
        db.deleteFrom(GROUP).where(GROUP.ID.eq(id)).execute();
    }

    int nextPosition() {
        return db.select(org.jooq.impl.DSL.coalesce(org.jooq.impl.DSL.max(GROUP.POSITION), -1))
                        .from(GROUP)
                        .fetchSingle()
                        .value1()
                + 1;
    }
}
