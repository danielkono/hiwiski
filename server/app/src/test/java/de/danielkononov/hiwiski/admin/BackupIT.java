package de.danielkononov.hiwiski.admin;

import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The acceptance case for backup and restore.
 *
 * <p>"Take a backup, throw the database away, restore, all devices sync again and lose
 * nothing."
 *
 * <p>A backup that was never restored is not a backup — that is why the restore path is in
 * the same phase as the backup path, and why this test checks it.
 */
@IntegrationTest
class BackupIT {

    private static final String LIST = "TODO_LIST";
    private static final String TODO_TYPE = "TODO";

    @Autowired RestTestClient rest;

    @Autowired DSLContext db;

    @Test
    void backUpThrowAwayRestore() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);

        UUID listId = UUID.randomUUID();
        UUID todoId = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(TODO_TYPE, todoId, null, Map.of("title", "Müll rausbringen")), LIST, listId));
        device.pullAll();

        var oldInstanceId = handshakeInstanceId();

        var backup = rest.post()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        // The identifier carries the schema and server version -- without them nobody
        // restoring would know where the archive came from.
        assertThat(backup.get("schemaVersion")).isNotNull();
        assertThat(backup.get("serverVersion")).isNotNull();

        // Throw the database away -- as far as a test can.
        db.deleteFrom(TODO).execute();
        db.deleteFrom(TODO_LIST).execute();
        assertThat(db.fetchCount(TODO_LIST)).isZero();

        var result = rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        // Nothing is lost.
        assertThat(db.fetchCount(TODO_LIST)).isEqualTo(1);
        assertThat(db.select(TODO.TITLE).from(TODO).fetchOne(TODO.TITLE)).isEqualTo("Müll rausbringen");

        // And it can be found again: the search index is not in the archive, and the
        // restore emptied it.
        de.danielkononov.hiwiski.support.FollowUps.await(db);
        var found = rest.get()
                .uri("/api/v1/search?q={q}", "Müll")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((java.util.List<?>) found.get("hits")).isNotEmpty();

        // The instance ID is new. Without it devices would silently keep working on a
        // state that no longer exists -- the worst conceivable data loss in this app.
        assertThat(result.get("instanceId")).isNotEqualTo(oldInstanceId);
        assertThat(handshakeInstanceId()).isEqualTo(result.get("instanceId"));
    }

    /**
     * A page refers to its parent in the same table. Edited after its child was created,
     * the parent comes after the child in the table -- and the dump; restored in that
     * order, the child's insert broke the foreign key, and the backup could never be
     * restored.
     */
    @Test
    void pagesComeBackParentsFirst() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID parent = UUID.randomUUID();
        UUID child = UUID.randomUUID();
        UUID grandchild = UUID.randomUUID();
        long version = ((Number) device.push(SyncClient.mutation(
                        "WIKI_PAGE", parent, null, Map.of("title", "Haus", "kind", "PAGE", "content", "")))
                .getFirst()
                .get("version"))
                .longValue();
        device.push(SyncClient.withContainer(
                SyncClient.mutation("WIKI_PAGE", child, null, Map.of("title", "Technik", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                parent));
        device.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "WIKI_PAGE", grandchild, null, Map.of("title", "Router", "kind", "PAGE", "content", "")),
                "WIKI_PAGE",
                child));
        // The parent changes last, so its current row is written after the others.
        device.push(SyncClient.mutation("WIKI_PAGE", parent, version, Map.of("title", "Unser Haus")));

        var backup = rest.post()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk();
        assertThat(db.fetchCount(de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE)).isEqualTo(3);
    }

    /** Two backups in the same second get archives of their own, and nothing half-written stays. */
    @Test
    void backupsInTheSameSecondDoNotShareAnArchive(
            @org.springframework.beans.factory.annotation.Value("${hiwiski.backup-path}") String backupPath)
            throws java.io.IOException {
        var session = Family.setUp(rest);
        var ids = new java.util.HashSet<Object>();
        for (int i = 0; i < 3; i++) {
            ids.add(rest.post()
                    .uri("/api/v1/admin/backups")
                    .headers(session.auth())
                    .exchange()
                    .expectStatus()
                    .isCreated()
                    .expectBody(Map.class)
                    .returnResult()
                    .getResponseBody()
                    .get("id"));
        }

        assertThat(ids).hasSize(3);
        try (var files = java.nio.file.Files.list(java.nio.file.Path.of(backupPath))) {
            assertThat(files.map(path -> path.getFileName().toString())).noneMatch(name -> name.endsWith(".part"));
        }
    }

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

    /** After a restore the images are the archive's -- none from after the backup stay. */
    @Test
    void theImagesAreTheArchives(
            @org.springframework.beans.factory.annotation.Value("${hiwiski.media-path}") String mediaPath)
            throws java.io.IOException {
        var session = Family.setUp(rest);
        var backup = backUp(session);
        var later = java.nio.file.Files.createDirectories(java.nio.file.Path.of(mediaPath)).resolve("f".repeat(64));
        java.nio.file.Files.writeString(later, "uploaded after the backup");

        rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk();

        assertThat(later).doesNotExist();
    }

    @Test
    void aDeviceWithAPendingOutboxSurvivesTheRestore() {
        var session = Family.setUp(rest);
        var device = new SyncClient(rest, session);
        UUID listId = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, listId, null, Map.of("name", "Haushalt")));
        device.pullAll();

        var backup = rest.post()
                .uri("/api/v1/admin/backups")
                .headers(session.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        // The device creates something else -- that is not in the backup.
        UUID later = UUID.randomUUID();
        device.push(SyncClient.mutation(LIST, later, null, Map.of("name", "Garten")));

        rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk();

        // The token is still valid -- it was in the backup. And the device can still
        // flush its outbox: what it has is not lost, it just has not arrived yet.
        var retried = device.push(SyncClient.mutation(LIST, later, null, Map.of("name", "Garten")));
        assertThat(retried.get(0).get("status")).isIn("applied", "duplicate");

        assertThat(db.fetchCount(TODO_LIST)).isEqualTo(2);
    }

    @Test
    void onlyTheAdministratorBacksUp() {
        var admin = Family.setUp(rest);
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(admin.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var bensSignIn = rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", "ben",
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var ben = Family.toSession(bensSignIn);

        rest.post()
                .uri("/api/v1/admin/backups")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isForbidden();
    }

    private Object handshakeInstanceId() {
        return rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("instanceId");
    }

    /** Every type keeps a key prefix of its own -- two with the same one collide. */
    @Test
    void twoTypesCannotShareAKeyPrefix() {
        var session = Family.setUp(rest);
        rest.put()
                .uri("/api/v1/admin/settings")
                .headers(session.auth())
                .contentType(org.springframework.http.MediaType.APPLICATION_JSON)
                .body(Map.of("keyPrefixRecipe", "wiki"))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("admin.key_prefix_taken");
    }
}
