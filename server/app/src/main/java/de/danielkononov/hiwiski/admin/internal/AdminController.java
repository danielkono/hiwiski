package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.api.AdminApi;
import de.danielkononov.hiwiski.api.model.BackupFailure;
import de.danielkononov.hiwiski.api.model.BackupInfo;
import de.danielkononov.hiwiski.api.model.BackupList;
import de.danielkononov.hiwiski.api.model.BackupPasswordChange;
import de.danielkononov.hiwiski.api.model.BackupPasswordEntry;
import de.danielkononov.hiwiski.api.model.BackupPasswordReset;
import de.danielkononov.hiwiski.api.model.BackupPreview;
import de.danielkononov.hiwiski.api.model.BackupStatus;
import de.danielkononov.hiwiski.api.model.InstanceSettings;
import de.danielkononov.hiwiski.api.model.LogLines;
import de.danielkononov.hiwiski.api.model.RestoreResult;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.SettingKey;
import java.io.IOException;
import java.nio.file.Files;
import java.time.Instant;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/** Settings, backups, log — administrator only. */
@RestController
class AdminController implements AdminApi {

    /** Minimum log retention (Settings). */
    private static final int MINIMUM_LOG_DAYS = 14;

    private final de.danielkononov.hiwiski.platform.InstanceSettings settings;
    private final BackupService backups;

    AdminController(de.danielkononov.hiwiski.platform.InstanceSettings settings, BackupService backups) {
        this.settings = settings;
        this.backups = backups;
    }

    @Override
    public ResponseEntity<InstanceSettings> getInstanceSettings() {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.ok(current());
    }

    @Override
    public ResponseEntity<InstanceSettings> setInstanceSettings(InstanceSettings request) {
        var principal = CurrentUser.require();
        principal.requireAdmin();

        Map<String, String> values = new LinkedHashMap<>();
        put(values, SettingKey.FAMILY_NAME, request.getFamilyName());
        if (request.getTimezone() != null) {
            values.put(SettingKey.FAMILY_TIMEZONE, zone(request.getTimezone()));
        }
        put(values, SettingKey.KEY_PREFIX_TODO, request.getKeyPrefixTodo());
        put(values, SettingKey.KEY_PREFIX_EVENT, request.getKeyPrefixEvent());
        put(values, SettingKey.KEY_PREFIX_WIKI_PAGE, request.getKeyPrefixWikiPage());
        put(values, SettingKey.KEY_PREFIX_RECIPE, request.getKeyPrefixRecipe());
        put(values, SettingKey.KEY_PREFIX_TODO_LIST, request.getKeyPrefixTodoList());
        if (request.getTrashRetentionDays() != null) {
            values.put(SettingKey.RETENTION_TRASH_DAYS, String.valueOf(Math.max(1, request.getTrashRetentionDays())));
        }
        if (request.getLogRetentionDays() != null) {
            // The log retention also limits how far the history reaches. Below 14 days it
            // would be useless, and the UI says so.
            if (request.getLogRetentionDays() < MINIMUM_LOG_DAYS) {
                throw HiwiskiException.invalid("admin.log_retention_too_short", "minimum", MINIMUM_LOG_DAYS);
            }
            values.put(SettingKey.RETENTION_LOG_DAYS, String.valueOf(request.getLogRetentionDays()));
        }
        putSchedule(values, request);
        requireDistinctPrefixes(values);
        settings.putAll(values, principal.memberId());
        if (request.getBackupKeep() != null) {
            // Lowered, the oldest go at once -- the app said first how many.
            backups.directory().prune(backups.schedule().keep());
        }
        return ResponseEntity.ok(current());
    }

    @Override
    public ResponseEntity<BackupList> listBackups() {
        CurrentUser.require().requireAdmin();
        var list = backups.list().stream().map(this::toApi).toList();
        return ResponseEntity.ok(new BackupList(list, toApi(backups.status(Instant.now()))));
    }

    @Override
    public ResponseEntity<BackupInfo> createBackup() {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.status(HttpStatus.CREATED).body(toApi(backups.create(BackupReason.ON_DEMAND)));
    }

    @Override
    public ResponseEntity<BackupPreview> inspectBackup(String id, BackupPasswordEntry entry) {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.ok(toApi(backups.inspect(backups.archive(id).file(), entry.getPassword())));
    }

    @Override
    public ResponseEntity<RestoreResult> restoreBackup(String id, BackupPasswordEntry entry) {
        CurrentUser.require().requireAdmin();
        var outcome = backups.restore(backups.archive(id).file(), entry.getPassword());
        return ResponseEntity.ok(new RestoreResult(outcome.instanceId(), (int) outcome.rows()));
    }

    @Override
    public ResponseEntity<BackupPreview> inspectUploadedBackup(String id, BackupPasswordEntry entry) {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.ok(toApi(backups.inspect(backups.uploaded(id), entry.getPassword())));
    }

    @Override
    public ResponseEntity<RestoreResult> restoreUploadedBackup(String id, BackupPasswordEntry entry)
            throws IOException {
        CurrentUser.require().requireAdmin();
        var file = backups.uploaded(id);
        var outcome = backups.restore(file, entry.getPassword());
        // Never kept: restored, it goes.
        Files.deleteIfExists(file);
        return ResponseEntity.ok(new RestoreResult(outcome.instanceId(), (int) outcome.rows()));
    }

    @Override
    public ResponseEntity<Void> changeBackupPassword(BackupPasswordChange request) {
        CurrentUser.require().requireAdmin();
        backups.changePassword(request.getCurrentPassword(), request.getNewPassword());
        return ResponseEntity.noContent().build();
    }

    @Override
    public ResponseEntity<Void> resetBackupPassword(BackupPasswordReset request) {
        CurrentUser.require().requireAdmin();
        backups.resetPassword(request.getNewPassword());
        return ResponseEntity.noContent().build();
    }

    @Override
    public ResponseEntity<LogLines> getLogs(Integer limit) {
        CurrentUser.require().requireAdmin();
        return ResponseEntity.ok(new LogLines(LogBuffer.tail(limit == null ? 500 : limit)));
    }

    /**
     * Every type keeps a prefix of its own. Each counts on its own counter: with the
     * recipe prefix set to the wiki's, wiki page 3 and recipe 3 were both `WIKI-3`, and
     * the second push failed on the unique key -- across types, the search index
     * refused the second item and it was never found.
     */
    private void requireDistinctPrefixes(Map<String, String> values) {
        Map<String, de.danielkononov.hiwiski.platform.KeyedEntityType> taken = new java.util.HashMap<>();
        for (var type : de.danielkononov.hiwiski.platform.KeyedEntityType.values()) {
            String prefix = values.getOrDefault(type.settingKey(), settings.get(type.settingKey(), type.defaultPrefix()))
                    .toUpperCase(java.util.Locale.ROOT);
            if (taken.putIfAbsent(prefix, type) != null) {
                throw HiwiskiException.invalid("admin.key_prefix_taken", "prefix", prefix);
            }
        }
    }

    /** The schedule: daily or weekly, the weekday, the time, how many are kept. There is no "off". */
    private static void putSchedule(Map<String, String> values, InstanceSettings request) {
        if (request.getBackupFrequency() != null) {
            values.put(SettingKey.BACKUP_FREQUENCY, request.getBackupFrequency().getValue());
        }
        if (request.getBackupWeekday() != null) {
            if (request.getBackupWeekday() < 1 || request.getBackupWeekday() > 7) {
                throw HiwiskiException.invalid("admin.backup_weekday_invalid", "weekday", request.getBackupWeekday());
            }
            values.put(SettingKey.BACKUP_WEEKDAY, String.valueOf(request.getBackupWeekday()));
        }
        if (request.getBackupTime() != null) {
            try {
                values.put(
                        SettingKey.BACKUP_TIME,
                        LocalTime.parse(request.getBackupTime().trim(), TYPED_TIME).format(HOUR_MINUTE));
            } catch (DateTimeParseException e) {
                throw HiwiskiException.invalid("admin.backup_time_invalid", "time", request.getBackupTime());
            }
        }
        if (request.getBackupKeep() != null) {
            if (request.getBackupKeep() < 1 || request.getBackupKeep() > BackupSchedule.KEEP_MAX) {
                throw HiwiskiException.invalid(
                        "admin.backup_keep_invalid", "minimum", 1, "maximum", BackupSchedule.KEEP_MAX);
            }
            values.put(SettingKey.BACKUP_KEEP, String.valueOf(request.getBackupKeep()));
        }
    }

    private static final DateTimeFormatter HOUR_MINUTE = DateTimeFormatter.ofPattern("HH:mm");

    /** As typed: {@code 3:30} as well as {@code 03:30}. */
    private static final DateTimeFormatter TYPED_TIME = DateTimeFormatter.ofPattern("H:mm");

    private InstanceSettings current() {
        InstanceSettings result = new InstanceSettings();
        settings.find(SettingKey.FAMILY_NAME).ifPresent(result::setFamilyName);
        settings.find(SettingKey.FAMILY_TIMEZONE).ifPresent(result::setTimezone);
        result.setKeyPrefixTodo(settings.get(SettingKey.KEY_PREFIX_TODO, "TD"));
        result.setKeyPrefixEvent(settings.get(SettingKey.KEY_PREFIX_EVENT, "EVT"));
        result.setKeyPrefixWikiPage(settings.get(SettingKey.KEY_PREFIX_WIKI_PAGE, "WIKI"));
        result.setKeyPrefixRecipe(settings.get(SettingKey.KEY_PREFIX_RECIPE, "REC"));
        result.setKeyPrefixTodoList(settings.get(SettingKey.KEY_PREFIX_TODO_LIST, "LST"));
        result.setTrashRetentionDays(settings.getInt(SettingKey.RETENTION_TRASH_DAYS, 30));
        result.setLogRetentionDays(settings.getInt(SettingKey.RETENTION_LOG_DAYS, 90));
        var schedule = backups.schedule();
        result.setBackupFrequency(InstanceSettings.BackupFrequencyEnum.fromValue(schedule.frequency().name()));
        result.setBackupWeekday(schedule.weekday().getValue());
        result.setBackupTime(schedule.time().format(HOUR_MINUTE));
        result.setBackupKeep(schedule.keep());
        return result;
    }

    private static void put(Map<String, String> values, String key, String value) {
        if (value != null && !value.isBlank()) {
            values.put(key, value.trim());
        }
    }

    private static String zone(String value) {
        try {
            return ZoneId.of(value).getId();
        } catch (RuntimeException e) {
            throw HiwiskiException.invalid("setup.timezone_invalid", "timezone", value);
        }
    }

    private BackupInfo toApi(BackupArchive archive) {
        var info = archive.header().info();
        BackupInfo result = new BackupInfo(
                archive.id(),
                utc(info.createdAt()),
                archive.bytes(),
                info.serverVersion(),
                info.schemaVersion(),
                BackupInfo.ReasonEnum.fromValue(info.reason().name()),
                backups.isCurrentKey(info.recipient()));
        result.setUpdateTo(info.updateTo());
        return result;
    }

    private static BackupStatus toApi(BackupService.Status status) {
        BackupStatus result = new BackupStatus(status.directory(), status.passwordSet());
        if (status.lastBackupAt() != null) {
            result.setLastBackupAt(utc(status.lastBackupAt()));
        }
        result.setNextDueAt(utc(status.nextDueAt()));
        if (status.failure() != null) {
            BackupFailure failure = new BackupFailure(
                    utc(status.failure().at()), BackupFailure.ReasonEnum.fromValue(status.failure().reason().name()));
            failure.setTrigger(BackupFailure.TriggerEnum.fromValue(status.failure().trigger().name()));
            result.setFailure(failure);
        }
        return result;
    }

    static BackupPreview toApi(BackupService.Preview preview) {
        var manifest = preview.manifest();
        BackupPreview result = new BackupPreview(
                utc(manifest.createdAt()),
                manifest.serverVersion(),
                manifest.schemaVersion(),
                preview.bytes(),
                manifest.members());
        result.setFamilyName(manifest.familyName());
        return result;
    }

    private static OffsetDateTime utc(Instant instant) {
        return OffsetDateTime.ofInstant(instant, ZoneOffset.UTC);
    }
}
