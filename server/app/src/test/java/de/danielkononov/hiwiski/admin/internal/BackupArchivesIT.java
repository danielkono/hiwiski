package de.danielkononov.hiwiski.admin.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.platform.StartRefused;
import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The archive as it leaves the machine: encrypted, downloadable,
 * uploadable, restorable with its password only -- on this version, an older one, and a
 * fresh server.
 */
@IntegrationTest
class BackupArchivesIT {

    private static final String LIST = "TODO_LIST";
    private static final String PASSWORD = Family.BACKUP_PASSWORD;

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Autowired de.danielkononov.hiwiski.platform.RestoreInProgress restoring;

    @Value("${hiwiski.backup-path}")
    String backupPath;

    @Value("${hiwiski.media-path}")
    String mediaPath;

    /**
     * The backup directory belongs to the Spring context, not to the test: what the test
     * before left there would be counted here.
     */
    @org.junit.jupiter.api.BeforeEach
    void emptyTheBackupDirectory() throws java.io.IOException {
        BackupService.deleteTree(Path.of(backupPath));
    }

    // --- Encryption --------------------------------------------------------------

    /** There is no unencrypted archive: nothing of the family's data is readable in it. */
    @Test
    void theArchiveIsEncrypted() throws Exception {
        var session = Family.setUp(rest);
        new SyncClient(rest, session).push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Geheimliste")));

        var file = fileOf(backUp(session));
        String raw = new String(Files.readAllBytes(file), StandardCharsets.ISO_8859_1);

        assertThat(raw).startsWith("HIWISKI-BACKUP\n").contains("age-encryption.org/v1");
        assertThat(raw).doesNotContain("Geheimliste").doesNotContain("Familie Probe").doesNotContain("anna");
        assertThat(TestArchives.open(file, PASSWORD)).containsKey("data/todo_list.jsonl");
    }

    /** The password comes before the preview, and a wrong one changes nothing. */
    @Test
    void aWrongPasswordChangesNothing() {
        var session = Family.setUp(rest);
        var backup = backUp(session);
        new SyncClient(rest, session).push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Neu")));

        post(session, "/api/v1/admin/backups/" + backup.get("id") + "/inspect", Map.of("password", "falsch-falsch"))
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_password_wrong");
        post(session, "/api/v1/admin/backups/" + backup.get("id") + "/restore", Map.of("password", "falsch-falsch"))
                .expectStatus()
                .isBadRequest();

        assertThat(db.fetchCount(TODO_LIST)).isEqualTo(1);
        assertThat(list(session)).hasSize(1);
    }

    @Test
    void thePreviewComesFromInside() {
        var session = Family.setUp(rest);
        var backup = backUp(session);

        post(session, "/api/v1/admin/backups/" + backup.get("id") + "/inspect", Map.of("password", PASSWORD))
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.members")
                .isEqualTo(1)
                .jsonPath("$.familyName")
                .isEqualTo("Familie Probe")
                .jsonPath("$.schemaVersion")
                .isEqualTo(backup.get("schemaVersion"));
    }

    /** A restore by mistake can be undone: the state it replaced is backed up first. */
    @Test
    void aRestoreBacksUpFirst() {
        var session = Family.setUp(rest);
        var backup = backUp(session);

        restore(session, backup).expectStatus().isOk();

        var archives = list(session);
        assertThat(archives).hasSize(2);
        assertThat(archives.getFirst().get("reason")).isEqualTo("BEFORE_RESTORE");
        assertThat(archives.get(1).get("reason")).isEqualTo("ON_DEMAND");
    }

    /**
     * While a backup is restored the instance is read-only for everyone, and the
     * handshake says so -- an app started again meanwhile still knows to wait.
     */
    @Test
    void nothingIsWrittenWhileARestoreRuns() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        restoring.begin();
        try {
            rest.get()
                    .uri("/api/v1/handshake")
                    .exchange()
                    .expectBody()
                    .jsonPath("$.restoring")
                    .isEqualTo(true);
            rest.post()
                    .uri("/api/v1/sync/push")
                    .headers(session.auth())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("mutations", List.of()))
                    .exchange()
                    .expectStatus()
                    .isEqualTo(503)
                    .expectHeader()
                    .valueEquals("Retry-After", "5")
                    .expectBody()
                    .jsonPath("$.code")
                    .isEqualTo("instance.restoring");
            // Reading goes on.
            rest.get().uri("/api/v1/admin/backups").headers(session.auth()).exchange().expectStatus().isOk();
        } finally {
            restoring.end();
        }
        device.push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Danach")));
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody()
                .jsonPath("$.restoring")
                .doesNotExist();
    }

    // --- Download and upload -------------------------------------------------------

    /** Downloaded, uploaded, restored -- the way an archive comes back from the drawer. */
    @Test
    void downloadUploadRestore() {
        var session = Family.setUp(rest);
        UUID listId = UUID.randomUUID();
        new SyncClient(rest, session).push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        var backup = backUp(session);

        byte[] downloaded = rest.get()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/file")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectHeader()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .expectBody(byte[].class)
                .returnResult()
                .getResponseBody();
        assertThat(downloaded).hasSize(((Number) backup.get("bytes")).intValue());

        db.deleteFrom(TODO_LIST).execute();
        var upload = upload(session, "/api/v1/admin/backups/uploads", downloaded);

        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/inspect", Map.of("password", PASSWORD))
                .expectStatus()
                .isOk();
        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/restore", Map.of("password", PASSWORD))
                .expectStatus()
                .isOk();

        assertThat(db.fetchCount(TODO_LIST)).isEqualTo(1);
        // Never kept: restored, it is gone -- and not in the backup directory either.
        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/inspect", Map.of("password", PASSWORD))
                .expectStatus()
                .isNotFound();
        assertThat(list(session)).extracting(archive -> archive.get("reason")).containsOnly("ON_DEMAND", "BEFORE_RESTORE");
    }

    @Test
    void anUploadThatIsNoArchiveIsRefused() {
        var session = Family.setUp(rest);

        rest.post()
                .uri("/api/v1/admin/backups/uploads")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body("PK\u0003\u0004 not an archive".getBytes(StandardCharsets.UTF_8))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_invalid");
    }

    /** Cut off on its way -- an interrupted copy to the NAS -- it fails before anything is replaced. */
    @Test
    void anArchiveCutOffIsRefused() throws Exception {
        var session = Family.setUp(rest);
        byte[] whole = Files.readAllBytes(fileOf(backUp(session)));
        byte[] cut = java.util.Arrays.copyOf(whole, whole.length - 40);
        var upload = upload(session, "/api/v1/admin/backups/uploads", cut);

        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/restore", Map.of("password", PASSWORD))
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_invalid");
        assertThat(db.fetchCount(de.danielkononov.hiwiski.db.generated.Tables.MEMBER)).isEqualTo(1);
    }

    /** An entry that climbs out of the archive's directory is refused, and writes nothing. */
    @Test
    void anArchiveCannotWriteOutsideItsDirectory() throws Exception {
        var session = Family.setUp(rest);
        var real = fileOf(backUp(session));
        var entries = new LinkedHashMap<>(TestArchives.open(real, PASSWORD));
        entries.put("media/../../../escaped.txt", "outside".getBytes(StandardCharsets.UTF_8));
        var crafted = Files.createTempFile("crafted", ".hiwiski");
        TestArchives.write(real, crafted, entries);
        var upload = upload(session, "/api/v1/admin/backups/uploads", Files.readAllBytes(crafted));

        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/restore", Map.of("password", PASSWORD))
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_invalid");
        try (var found = Files.walk(Path.of(mediaPath).toAbsolutePath().getParent())) {
            assertThat(found.map(path -> path.getFileName().toString())).doesNotContain("escaped.txt");
        }
    }

    // --- Versions ------------------------------------------------------------------

    /** One from a newer version stops at the preview, naming the version to install. */
    @Test
    void anArchiveFromANewerVersionIsRefused() throws Exception {
        var session = Family.setUp(rest);
        var real = fileOf(backUp(session));
        var entries = new LinkedHashMap<>(TestArchives.open(real, PASSWORD));
        entries.put(
                BackupWriter.MANIFEST,
                TestArchives.manifestWith(entries, Map.of("schemaVersion", "999", "serverVersion", "2031.1.0")));
        var newer = Files.createTempFile("newer", ".hiwiski");
        TestArchives.write(real, newer, entries);
        var upload = upload(session, "/api/v1/admin/backups/uploads", Files.readAllBytes(newer));

        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/inspect", Map.of("password", PASSWORD))
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_too_new")
                .jsonPath("$.params.serverVersion")
                .isEqualTo("2031.1.0");
    }

    /**
     * Another family's archive is refused on a running server: it would replace this
     * family by strangers. It belongs on a new instance, through the setup wizard.
     */
    @Test
    void anotherFamilysArchiveIsRefused() {
        var session = Family.setUp(rest);
        var backup = backUp(session);
        db.execute("update instance_setting set value = ? where key = 'family.id'", UUID.randomUUID().toString());

        inspect(session, backup, PASSWORD)
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_other_family")
                .jsonPath("$.params.familyName")
                .isEqualTo("Familie Probe");
        restore(session, backup).expectStatus().isBadRequest();
        assertThat(list(session)).hasSize(1);
    }

    /** Every archive names its family: one without is none of ours, and is refused. */
    @Test
    void anArchiveWithoutAFamilyIsRefused() throws Exception {
        var session = Family.setUp(rest);
        var real = fileOf(backUp(session));
        var entries = new LinkedHashMap<>(TestArchives.open(real, PASSWORD));
        var manifest = new LinkedHashMap<String, Object>(tools.jackson.databind.json.JsonMapper.builder()
                .build()
                .readValue(entries.get(BackupWriter.MANIFEST), Map.class));
        manifest.remove("familyId");
        entries.put(BackupWriter.MANIFEST, tools.jackson.databind.json.JsonMapper.builder().build().writeValueAsBytes(manifest));
        var foreign = Files.createTempFile("foreign", ".hiwiski");
        TestArchives.write(real, foreign, entries);
        var upload = upload(session, "/api/v1/admin/backups/uploads", Files.readAllBytes(foreign));

        post(session, "/api/v1/admin/backups/uploads/" + upload.get("id") + "/inspect", Map.of("password", PASSWORD))
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.backup_invalid");
    }

    /** Any version change backs up before the migration -- named so in the list. */
    @Test
    void anUpdateIsBackedUpFirst() {
        var session = Family.setUp(rest);
        db.execute("insert into instance_setting (key, value) values ('server.lastVersion', '2026.0.9') "
                + "on conflict (key) do update set value = excluded.value");

        TestArchives.backUpBeforeUpdate(db, Path.of(backupPath), Path.of(mediaPath), "2026.1.0");

        var archives = list(session);
        assertThat(archives).hasSize(1);
        assertThat(archives.getFirst())
                .containsEntry("reason", "BEFORE_UPDATE")
                .containsEntry("updateTo", "2026.1.0")
                .containsEntry("serverVersion", "2026.0.9");

        // The same version again: nothing to back up.
        db.execute("update instance_setting set value = '2026.1.0' where key = 'server.lastVersion'");
        TestArchives.backUpBeforeUpdate(db, Path.of(backupPath), Path.of(mediaPath), "2026.1.0");
        assertThat(list(session)).hasSize(1);
    }

    /** If the backup before an update fails, the server does not start -- and nothing is migrated. */
    @Test
    void aFailedBackupBeforeAnUpdateStopsTheStart() throws Exception {
        Family.setUp(rest);
        db.execute("insert into instance_setting (key, value) values ('server.lastVersion', '2026.0.9') "
                + "on conflict (key) do update set value = excluded.value");
        Path notADirectory = Files.createTempFile("backup", ".file");

        assertThatThrownBy(() -> TestArchives.backUpBeforeUpdate(db, notADirectory, Path.of(mediaPath), "2026.1.0"))
                .isInstanceOf(StartRefused.class)
                .hasMessageContaining("2026.1.0");
    }

    // --- The backup password ---------------------------------------------------------

    /**
     * A new password wraps the same key anew, in the archives too; the old one opens
     * nothing any more.
     */
    @Test
    void aChangedPasswordOpensTheArchivesMadeBefore() {
        var session = Family.setUp(rest);
        var backup = backUp(session);

        rest.put()
                .uri("/api/v1/admin/backup-password")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", "falsch-falsch", "newPassword", "ein-neues-backup-passwort"))
                .exchange()
                .expectStatus()
                .isBadRequest();
        rest.put()
                .uri("/api/v1/admin/backup-password")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", PASSWORD, "newPassword", "ein-neues-backup-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();

        inspect(session, backup, PASSWORD).expectStatus().isBadRequest();
        inspect(session, backup, "ein-neues-backup-passwort").expectStatus().isOk();
        inspect(session, backUp(session), "ein-neues-backup-passwort").expectStatus().isOk();
        assertThat(list(session)).allSatisfy(archive -> assertThat(archive.get("currentKey")).isEqualTo(true));
    }

    /**
     * A forgotten password: a new key pair. What comes after opens with the new one; what
     * came before only with the old -- there is no back door.
     */
    @Test
    void aNewPasswordWithoutTheOldIsANewKey() {
        var session = Family.setUp(rest);
        var before = backUp(session);

        rest.post()
                .uri("/api/v1/admin/backup-password/reset")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("newPassword", "ganz-neues-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();
        var after = backUp(session);

        inspect(session, before, "ganz-neues-passwort").expectStatus().isBadRequest();
        inspect(session, before, PASSWORD).expectStatus().isOk();
        inspect(session, after, "ganz-neues-passwort").expectStatus().isOk();
        var archives = list(session);
        assertThat(archives.getFirst().get("currentKey")).isEqualTo(true);
        assertThat(archives.get(1).get("currentKey")).isEqualTo(false);
    }

    /** A restore keeps the current backup key: an old archive does not bring back an old password. */
    @Test
    void aRestoreKeepsTheCurrentBackupPassword() {
        var session = Family.setUp(rest);
        var backup = backUp(session);
        rest.put()
                .uri("/api/v1/admin/backup-password")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", PASSWORD, "newPassword", "ein-neues-backup-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();

        restore(session, backup, "ein-neues-backup-passwort").expectStatus().isOk();

        inspect(session, backUp(session), "ein-neues-backup-passwort").expectStatus().isOk();
    }

    // --- A fresh server ------------------------------------------------------------------

    /**
     * A new machine after the old one is gone: the setup wizard restores an archive.
     * Members and the administrator come from it, and so does the backup key -- with the
     * password just typed.
     */
    @Test
    void aFreshServerIsSetUpFromAnArchive() throws Exception {
        var session = Family.setUp(rest);
        new SyncClient(rest, session).push(SyncClient.mutation(LIST, UUID.randomUUID(), null, Map.of("name", "Haushalt")));
        byte[] archive = Files.readAllBytes(fileOf(backUp(session)));
        new de.danielkononov.hiwiski.support.DatabaseCleaner().clean(db);

        rest.post()
                .uri("/api/v1/setup/uploads")
                .header("X-Hiwiski-Setup-Code", "WRONG")
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(archive)
                .exchange()
                .expectStatus()
                .isForbidden();
        var upload = rest.post()
                .uri("/api/v1/setup/uploads")
                .header("X-Hiwiski-Setup-Code", Family.SETUP_CODE)
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(archive)
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        setupCall("/api/v1/setup/uploads/" + upload.get("id") + "/inspect", "falsch-falsch")
                .expectStatus()
                .isBadRequest();
        setupCall("/api/v1/setup/uploads/" + upload.get("id") + "/inspect", PASSWORD)
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.members")
                .isEqualTo(1);
        setupCall("/api/v1/setup/uploads/" + upload.get("id") + "/restore", PASSWORD)
                .expectStatus()
                .isOk();

        assertThat(db.fetchCount(TODO_LIST)).isEqualTo(1);
        var anna = Family.login(rest, "anna", "geheim-genug", "Neues Handy");
        inspect(anna, backUp(anna), PASSWORD).expectStatus().isOk();
        // Set up now: the wizard is closed.
        setupCall("/api/v1/setup/uploads/" + upload.get("id") + "/inspect", PASSWORD)
                .expectStatus()
                .isEqualTo(409);
    }

    @Test
    void theSetupAsksForABackupPasswordOfItsOwn() {
        var body = new LinkedHashMap<String, Object>(Map.of(
                "setupCode", Family.SETUP_CODE,
                "familyName", "Familie Probe",
                "timezone", "Europe/Berlin",
                "admin", Map.of("displayName", "Anna", "username", "anna", "password", "geheim-genug"),
                "device", Map.of("deviceName", "Annas iPhone", "platform", "IOS"),
                "backupPassword", "geheim-genug"));

        rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("setup.backup_password_same");
    }

    // --- Schedule ------------------------------------------------------------------------

    /** Frequency, time and the number kept are settings; lowering the number deletes the oldest. */
    @Test
    void theScheduleIsASetting() {
        var session = Family.setUp(rest);
        backUp(session);
        backUp(session);
        backUp(session);

        rest.put()
                .uri("/api/v1/admin/settings")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("backupFrequency", "WEEKLY", "backupWeekday", 7, "backupTime", "3:30", "backupKeep", 2))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.backupFrequency")
                .isEqualTo("WEEKLY")
                .jsonPath("$.backupTime")
                .isEqualTo("03:30")
                .jsonPath("$.backupKeep")
                .isEqualTo(2);

        assertThat(list(session)).hasSize(2);
        rest.get()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.status.nextDueAt")
                .exists()
                .jsonPath("$.status.passwordSet")
                .isEqualTo(true);
    }

    /** A failed backup is shown with its reason until the next one succeeds. */
    @Test
    void aFailedBackupIsShown() throws Exception {
        var session = Family.setUp(rest);
        Path directory = Path.of(backupPath);
        Files.createDirectories(directory);
        var writable = directory.toFile();
        assertThat(writable.setWritable(false)).isTrue();
        try {
            rest.post()
                    .uri("/api/v1/admin/backups")
                    .headers(session.auth())
                    .exchange()
                    .expectStatus()
                    .isEqualTo(503)
                    .expectBody()
                    .jsonPath("$.params.reason")
                    .isEqualTo("DIRECTORY_NOT_WRITABLE");
            rest.get()
                    .uri("/api/v1/admin/backups")
                    .headers(session.auth())
                    .exchange()
                    .expectBody()
                    .jsonPath("$.status.failure.reason")
                    .isEqualTo("DIRECTORY_NOT_WRITABLE")
                    .jsonPath("$.status.failure.trigger")
                    .isEqualTo("ON_DEMAND");
        } finally {
            writable.setWritable(true);
        }
        backUp(session);
        rest.get()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.status.failure")
                .doesNotExist();
    }

    // --- Helpers ---------------------------------------------------------------------------

    private Map<?, ?> backUp(Family.Session session) {
        return rest.post()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> list(Family.Session session) {
        return (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("backups");
    }

    private Path fileOf(Map<?, ?> backup) {
        return Path.of(backupPath).resolve(backup.get("id") + BackupDirectory.SUFFIX);
    }

    private RestTestClient.ResponseSpec post(Family.Session session, String uri, Object body) {
        return rest.post()
                .uri(uri)
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .exchange();
    }

    private RestTestClient.ResponseSpec inspect(Family.Session session, Map<?, ?> backup, String password) {
        return post(session, "/api/v1/admin/backups/" + backup.get("id") + "/inspect", Map.of("password", password));
    }

    private RestTestClient.ResponseSpec restore(Family.Session session, Map<?, ?> backup) {
        return restore(session, backup, PASSWORD);
    }

    private RestTestClient.ResponseSpec restore(Family.Session session, Map<?, ?> backup, String password) {
        return post(session, "/api/v1/admin/backups/" + backup.get("id") + "/restore", Map.of("password", password));
    }

    private Map<?, ?> upload(Family.Session session, String uri, byte[] bytes) {
        return rest.post()
                .uri(uri)
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(bytes)
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    private RestTestClient.ResponseSpec setupCall(String uri, String password) {
        return rest.post()
                .uri(uri)
                .header("X-Hiwiski-Setup-Code", Family.SETUP_CODE)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("password", password))
                .exchange();
    }
}
