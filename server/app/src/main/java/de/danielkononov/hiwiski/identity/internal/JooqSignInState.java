package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.DEVICE;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;

import de.danielkononov.hiwiski.db.generated.tables.records.DeviceRecord;
import de.danielkononov.hiwiski.identity.SignInState;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.jooq.DSLContext;
import org.springframework.stereotype.Component;

/** {@link SignInState} straight on the tables, inside the restore's transaction. */
@Component
class JooqSignInState implements SignInState {

    private record Credentials(UUID memberId, String passwordHash, boolean mustChange, OffsetDateTime disabledAt) {}

    private record Captured(List<Credentials> members, List<DeviceRecord> devices) implements Snapshot {}

    private final DSLContext db;

    JooqSignInState(DSLContext db) {
        this.db = db;
    }

    @Override
    public Snapshot capture() {
        List<Credentials> members = db.select(
                        MEMBER.ID, MEMBER.PASSWORD_HASH, MEMBER.MUST_CHANGE_PASSWORD, MEMBER.DISABLED_AT)
                .from(MEMBER)
                .fetch(row -> new Credentials(row.value1(), row.value2(), row.value3(), row.value4()));
        return new Captured(members, db.selectFrom(DEVICE).fetch());
    }

    @Override
    public void carryOver(Snapshot snapshot) {
        var captured = (Captured) snapshot;
        for (Credentials member : captured.members()) {
            db.update(MEMBER)
                    .set(MEMBER.PASSWORD_HASH, member.passwordHash())
                    .set(MEMBER.MUST_CHANGE_PASSWORD, member.mustChange())
                    .set(MEMBER.DISABLED_AT, member.disabledAt())
                    .where(MEMBER.ID.eq(member.memberId()))
                    .execute();
        }

        Map<UUID, DeviceRecord> now =
                captured.devices().stream().collect(Collectors.toMap(DeviceRecord::getId, Function.identity()));
        Set<UUID> restored = Set.copyOf(db.select(DEVICE.ID).from(DEVICE).fetch(DEVICE.ID));
        Set<UUID> existingMembers = Set.copyOf(db.select(MEMBER.ID).from(MEMBER).fetch(MEMBER.ID));

        for (UUID id : restored) {
            DeviceRecord current = now.get(id);
            // One the current database does not know stays as the archive has it:
            // that is the archive of another instance, restored to move the family to
            // a new server (site: "Moving"), and its devices go on there.
            //
            // When it was last seen and whether it stays signed in come along too: from
            // a backup older than twelve hours the archive's last_seen_at expired every
            // session at once -- the browser that ran the restore included.
            if (current != null) {
                db.update(DEVICE)
                        .set(DEVICE.REVOKED_AT, current.getRevokedAt())
                        .set(DEVICE.TOKEN_HASH, current.getTokenHash())
                        .set(DEVICE.LAST_SEEN_AT, current.getLastSeenAt())
                        .set(DEVICE.STAY_SIGNED_IN, current.getStaySignedIn())
                        .where(DEVICE.ID.eq(id))
                        .execute();
            }
        }
        // Registered since the backup -- the device running the restore, as a rule.
        for (DeviceRecord current : captured.devices()) {
            if (!restored.contains(current.getId()) && existingMembers.contains(current.getMemberId())) {
                DeviceRecord copy = db.newRecord(DEVICE, current);
                copy.changed(true);
                copy.insert();
            }
        }
    }
}
