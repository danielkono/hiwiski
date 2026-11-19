package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.MemberInfo;
import de.danielkononov.hiwiski.identity.SetupBackupKey;
import de.danielkononov.hiwiski.identity.SetupCompleted;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The initial configuration -- exactly once, for the first person.
 *
 * <p>Afterwards {@code setup.completed} is set and the wizard is never reachable again.
 */
@Service
class SetupService {

    /**
     * Two groups are suggested.
     *
     * <p>The first is the one every new member goes into -- which is why "Everyone"
     * comes first (identity). Only used when the request names no
     * groups; the setup wizard suggests them in the language of its UI.
     */
    private static final List<String> DEFAULT_GROUPS = List.of("Everyone", "Parents");

    private final InstanceSettings settings;
    private final MemberService members;
    private final GroupService groups;
    private final AuthService auth;
    private final ApplicationEventPublisher events;
    private final SetupBackupKey backupKey;
    private final SetupLock lock;

    SetupService(
            InstanceSettings settings,
            MemberService members,
            GroupService groups,
            AuthService auth,
            ApplicationEventPublisher events,
            SetupBackupKey backupKey,
            SetupLock lock) {
        this.lock = lock;
        this.settings = settings;
        this.members = members;
        this.groups = groups;
        this.auth = auth;
        this.events = events;
        this.backupKey = backupKey;
    }

    boolean completed() {
        return settings.getBoolean(SettingKey.SETUP_COMPLETED, false);
    }

    /**
     * Everything in one transaction.
     *
     * <p>If a step fails, there is neither half a family nor an administrator without
     * groups -- and the wizard can be run again.
     */
    @Transactional
    AuthService.SignedIn run(
            String familyName,
            String timezone,
            UUID adminId,
            String adminDisplayName,
            String adminUsername,
            String adminPassword,
            List<String> groupNames,
            AuthService.NewDevice device,
            String language,
            String backupPassword) {

        // One at a time, with a restore from the wizard too: whoever comes second
        // waits here and then finds the instance set up.
        lock.hold();
        // Two barriers instead of one: the flag says the wizard has run; the member
        // count says someone already exists. A call slipping through between the two
        // would create a second administrator.
        if (completed() || members.anyMemberExists()) {
            throw HiwiskiException.conflict("setup.already_completed");
        }

        ZoneId zone = parseZone(timezone);
        requireOwnBackupPassword(backupPassword, adminPassword);

        List<String> names = (groupNames == null || groupNames.isEmpty()) ? DEFAULT_GROUPS : groupNames;
        UUID firstGroupId = null;
        for (String name : names) {
            var group = groups.create(name, defaultIcon(name), List.of());
            if (firstGroupId == null) {
                firstGroupId = group.id();
            }
        }

        MemberInfo admin =
                members.create(
                        adminId,
                        adminDisplayName,
                        adminUsername,
                        adminPassword,
                        "GREEN",
                        firstGroupId == null ? List.of() : List.of(firstGroupId),
                        true);

        Map<String, String> values = new LinkedHashMap<>();
        values.put(SettingKey.FAMILY_NAME, requireFamilyName(familyName));
        values.put(SettingKey.FAMILY_TIMEZONE, zone.getId());
        values.put(SettingKey.RETENTION_TRASH_DAYS, "30");
        values.put(SettingKey.RETENTION_LOG_DAYS, "90");
        values.put(SettingKey.INSTANCE_ID, UUID.randomUUID().toString());
        values.put(SettingKey.FAMILY_ID, UUID.randomUUID().toString());
        if (firstGroupId != null) {
            values.put(SettingKey.DEFAULT_GROUP, firstGroupId.toString());
        }
        values.put(SettingKey.SETUP_COMPLETED, "true");
        settings.putAll(values, admin.id());
        backupKey.create(backupPassword);
        // Inside the transaction: a failed seed leaves no family behind either.
        events.publishEvent(new SetupCompleted(language));

        // Signed in right away: otherwise the first person would have to log in again
        // immediately after creating the account, and nobody understands that.
        MemberRow row = members.row(admin.id()).orElseThrow();
        return auth.registerDevice(row, device);
    }

    /**
     * Every backup is locked with this password, and it is not the
     * administrator's: whoever knows one should not have the other by that alone.
     */
    private static void requireOwnBackupPassword(String backupPassword, String adminPassword) {
        if (backupPassword == null || backupPassword.isEmpty()) {
            throw HiwiskiException.invalid("setup.backup_password_required");
        }
        if (backupPassword.equals(adminPassword)) {
            throw HiwiskiException.invalid("setup.backup_password_same");
        }
    }

    private static String defaultIcon(String name) {
        // The wizard suggests the names in the language of its UI.
        return "Parents".equalsIgnoreCase(name) || "Eltern".equalsIgnoreCase(name) ? "diversity_1" : "group";
    }

    private static String requireFamilyName(String familyName) {
        if (familyName == null || familyName.isBlank()) {
            throw HiwiskiException.invalid("setup.family_name_required");
        }
        return MemberService.requireShort("familyName", familyName.trim());
    }

    private static ZoneId parseZone(String timezone) {
        try {
            return ZoneId.of(timezone);
        } catch (RuntimeException e) {
            throw HiwiskiException.invalid("setup.timezone_invalid", "timezone", String.valueOf(timezone));
        }
    }
}
