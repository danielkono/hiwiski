package de.danielkononov.hiwiski.security;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Identity rules found missing in a security review: invitation codes, sign-in throttles,
 * passwords and devices.
 *
 * <p>Every test asserts the secure behaviour. Cast: Anna is the administrator, Ben an
 * ordinary member who tries more than he should.
 */
@IntegrationTest
@SuppressWarnings("unchecked")
class IdentitySecurityIT {

    private static final String BENS_PASSWORD = "bens-langes-passwort";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        ben = invite("Ben", "ben", List.of());
    }

    // --- Invitation codes ----------------------------------------------------------

    /** Only the administrator sees the open invitations and their codes. */
    @Test
    void aMemberCannotReadTheOpenInvitationCodes() {
        UUID parents = groupId("Parents");
        rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("displayName", "Grandma", "validity", "HOURS_24", "groupIds", List.of(parents.toString())))
                .exchange()
                .expectStatus()
                .isCreated();

        rest.get()
                .uri("/api/v1/invitations")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isForbidden()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.admin_required");

        rest.get()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.invitations.length()")
                .isEqualTo(1);
    }

    // --- Sign-ins with made-up usernames ------------------------------------------

    /**
     * A loop through made-up usernames from one address meets that address's
     * budget. The address is the one the trusted proxy names (the test client is on
     * loopback, a trusted proxy).
     */
    @Test
    void madeUpUsernamesFromOneAddressRunIntoItsBudget() {
        String address = "203.0.113.8";
        int status = 0;
        int attempts = 0;
        while (attempts < 40 && status != 429) {
            status = login("nobody-" + attempts, "irgendwas-langes", address);
            attempts++;
        }
        assertThat(status).as("status after %s made-up usernames", attempts).isEqualTo(429);
        // Thirty free; the budget refills one every ten seconds while the loop runs.
        assertThat(attempts).isBetween(31, 34);

        // Another address -- a family member at home -- signs in as usual.
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.30")).isEqualTo(200);
    }

    /** The scheme a trusted proxy names counts -- Caddy's TLS reaches the handshake. */
    @Test
    void theHandshakeTakesTheSchemeFromTheTrustedProxy() {
        rest.get()
                .uri("/api/v1/handshake")
                .header("X-Forwarded-Proto", "https")
                .exchange()
                .expectBody()
                .jsonPath("$.cleartext")
                .isEqualTo(false);
        rest.get()
                .uri("/api/v1/handshake")
                .exchange()
                .expectBody()
                .jsonPath("$.cleartext")
                .isEqualTo(true);
    }

    /**
     * A stranger with many addresses -- an IPv6 /48 holds
     * 65,536 /64s -- meets one ceiling per username. It does not keep the member out:
     * their own installation, and an address they signed in from, still get in.
     */
    @Test
    void manyAddressesMeetTheUsernamesCeiling_butNotTheMembersOwnDevice() {
        invite("Carla", "carla", List.of());
        String phone = UUID.randomUUID().toString();
        assertThat(login("carla", BENS_PASSWORD, "192.168.1.40", phone)).isEqualTo(200);

        for (int i = 0; i < 100; i++) {
            assertThat(login("carla", "geraten-" + i, "198.51." + (100 + i / 200) + "." + (i % 200 + 1), null))
                    .as("guess %s, each from an address of its own", i)
                    .isEqualTo(401);
        }
        // The next guess, from yet another address: the ceiling.
        assertThat(login("carla", "geraten-x", "203.0.113.200", null)).isEqualTo(429);
        // A new device on a new network waits too, even with the right password, and a
        // made-up installation id is no key ...
        assertThat(login("carla", BENS_PASSWORD, "203.0.113.201", null)).isEqualTo(429);
        assertThat(login("carla", BENS_PASSWORD, "203.0.113.203", UUID.randomUUID().toString()))
                .isEqualTo(429);
        // ... but the member's own phone, from anywhere, and their home address get in.
        assertThat(login("carla", BENS_PASSWORD, "203.0.113.202", phone)).isEqualTo(200);
        assertThat(login("carla", BENS_PASSWORD, "192.168.1.40", null)).isEqualTo(200);
    }

    // --- Throttles and stored codes ---------------------------------------------

    /** Guessing codes runs into the address's budget; a valid code still works. */
    @Test
    void guessingInvitationCodesRunsIntoTheBudget() {
        String address = "203.0.113.10";
        int status = 0;
        int attempts = 0;
        while (attempts < 20 && status != 429) {
            status = rest.get()
                    .uri("/api/v1/invitations/ZZZZZ" + (10 + attempts))
                    .header("X-Forwarded-For", address)
                    .exchange()
                    .returnResult(Map.class)
                    .getStatus()
                    .value();
            attempts++;
        }
        assertThat(status).isEqualTo(429);
        assertThat(attempts).isEqualTo(11);

        // Somebody else, with the code they were given, joins as usual.
        var invitation = createInvitation();
        rest.get()
                .uri("/api/v1/invitations/" + invitation.get("code"))
                .header("X-Forwarded-For", "192.168.1.31")
                .exchange()
                .expectStatus()
                .isOk();
    }

    /** The code is stored as a hash and shown once, at creation. */
    @Test
    void theCodeIsStoredAsAHashAndShownOnce() {
        var invitation = createInvitation();
        String code = (String) invitation.get("code");
        assertThat(code).hasSize(7);

        var stored = db.fetchOne("select * from invitation where id = ?::uuid", invitation.get("id"));
        assertThat(stored.intoMap().values()).noneMatch(value -> value != null && value.toString().contains(code));
        // Slow and salted, not a SHA-256 a GPU reverses in seconds.
        assertThat(stored.get("code_hash", String.class)).startsWith("$argon2id$");

        var listed = (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("invitations");
        assertThat(listed).singleElement().satisfies(entry -> {
            assertThat(entry.get("code")).isNull();
            assertThat(entry.get("deepLink")).isNull();
            assertThat(entry).containsEntry("id", invitation.get("id"));
        });

        // Typed in lower case with the dash the UI shows, it still matches.
        rest.get()
                .uri("/api/v1/invitations/" + code.substring(0, 3).toLowerCase() + "-" + code.substring(3))
                .exchange()
                .expectStatus()
                .isOk();
    }

    /** A stolen token cannot guess the current password without limit. */
    @Test
    void guessingTheCurrentPasswordIsDelayed() {
        int status = 0;
        int attempts = 0;
        while (attempts < 10 && status != 429) {
            status = rest.post()
                    .uri("/api/v1/auth/password")
                    .headers(ben.auth())
                    .header("X-Forwarded-For", "203.0.113.11")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("currentPassword", "geraten-" + attempts, "newPassword", "ein-neues-passwort"))
                    .exchange()
                    .returnResult(Map.class)
                    .getStatus()
                    .value();
            attempts++;
        }
        assertThat(status).isEqualTo(429);
    }

    /**
     * An outsider sending wrong passwords for a known username does not keep its
     * owner out.
     */
    @Test
    void anOutsiderCannotLockAKnownUserOut() {
        for (int i = 0; i < 8; i++) {
            login("ben", "falsch-" + i, "203.0.113.12");
        }
        assertThat(login("ben", "falsch-x", "203.0.113.12")).isEqualTo(429);
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.32")).isEqualTo(200);
    }

    // --- Passwords and the devices signed in with them ----------------------------

    /** A password change signs out the member's other devices, not this one. */
    @Test
    void aPasswordChangeSignsOutTheOtherDevices() {
        var laptop = Family.login(rest, "ben", BENS_PASSWORD, "Bens Laptop");
        rest.post()
                .uri("/api/v1/auth/password")
                .headers(laptop.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", BENS_PASSWORD, "newPassword", "ein-neues-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isOk();
    }

    /**
     * After an administrator's reset, the earlier tokens do not come back once the
     * member has chosen a new password.
     */
    @Test
    void aResetSignsOutEveryDeviceForGood() {
        var laptop = Family.login(rest, "ben", BENS_PASSWORD, "Bens Laptop");
        String temporary = (String) rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/password-reset")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("temporaryPassword");

        var phone = Family.login(rest, "ben", temporary, "Bens Handy");
        rest.post()
                .uri("/api/v1/auth/password")
                .headers(phone.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", temporary, "newPassword", "ein-neues-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(phone.auth()).exchange().expectStatus().isOk();
    }

    // --- The administrator locks a member out -----------------------------------

    /** A disabled member is signed out everywhere and cannot sign in until enabled. */
    @Test
    void theAdministratorDisablesAndEnablesAMember() {
        var laptop = Family.login(rest, "ben", BENS_PASSWORD, "Bens Laptop");
        rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/disable")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isForbidden();

        rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/disable")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.disabled")
                .isEqualTo(true);

        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.33")).isEqualTo(401);

        rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/enable")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.disabled")
                .isEqualTo(false);
        // Signed out stays signed out; the password works again.
        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.33")).isEqualTo(200);
    }

    /** The administrator signs out a member's devices; the member signs in again. */
    @Test
    void theAdministratorSignsOutAMembersDevices() {
        var laptop = Family.login(rest, "ben", BENS_PASSWORD, "Bens Laptop");
        rest.post()
                .uri("/api/v1/members/" + ben.memberId() + "/sign-out")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(laptop.auth()).exchange().expectStatus().isUnauthorized();
        rest.get().uri("/api/v1/devices").headers(anna.auth()).exchange().expectStatus().isOk();
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.34")).isEqualTo(200);

        // Nobody disables or signs out the administrator from the family screen.
        rest.post()
                .uri("/api/v1/members/" + anna.memberId() + "/disable")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.member_is_admin");
    }

    // --- What a restore keeps as it is now ---------------------

    /**
     * A restore keeps the devices' activity as it is now -- an old archive does not
     * expire every session at once -- and the wall-board and feed addresses replaced
     * since the backup stay replaced.
     */
    @Test
    void aRestoreKeepsSessionsAliveAndReplacedAddressesReplaced() {
        // Ben's tablet is a session (no "Stay signed in"), idle for 13 hours in the archive.
        db.execute(
                "update device set stay_signed_in = false, last_seen_at = now() - interval '13 hours' where id = ?",
                ben.deviceId());
        UUID board = UUID.randomUUID();
        UUID feed = UUID.randomUUID();
        db.execute(
                "insert into board (id, owner_id, version, kind, name, token) values (?, ?, 1, 'DASHBOARD', 'Wall', ?)",
                board, ben.memberId(), "leaked-board-token-000000000000000");
        db.execute(
                "insert into calendar_feed (id, owner_id, version, name, calendar_ids, content_mode, token)"
                        + " values (?, ?, 1, 'Phone', ?, 'FULL', ?)",
                feed, ben.memberId(), new UUID[] {}, "leaked-feed-token-0000000000000000");

        var backup = rest.post()
                .uri("/api/v1/admin/backups")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        // Since the backup: the tablet was used, and both addresses were replaced.
        db.execute("update device set last_seen_at = now() where id = ?", ben.deviceId());
        db.execute("update board set token = 'new-board-token-00000000000000000000' where id = ?", board);
        db.execute("update calendar_feed set token = 'new-feed-token-000000000000000000000' where id = ?", feed);

        rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk();

        assertThat(db.fetchValue("select token from board where id = ?", board))
                .isEqualTo("new-board-token-00000000000000000000");
        assertThat(db.fetchValue("select token from calendar_feed where id = ?", feed))
                .isEqualTo("new-feed-token-000000000000000000000");
        assertThat(db.fetchValue(
                        "select last_seen_at > now() - interval '1 hour' from device where id = ?", ben.deviceId()))
                .isEqualTo(true);
        // And the session still works.
        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isOk();
    }

    // --- Restoring a backup --------------------------------------------------------

    /**
     * Restoring an older backup does not bring back a device revoked or a
     * password changed since; a device registered since stays signed in.
     */
    @Test
    void aRestoreKeepsWhoMaySignInAsItIsNow() {
        var stolenLaptop = Family.login(rest, "ben", BENS_PASSWORD, "Bens Laptop");
        var backup = rest.post()
                .uri("/api/v1/admin/backups")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        rest.delete()
                .uri("/api/v1/devices/" + stolenLaptop.deviceId())
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isNoContent();
        rest.post()
                .uri("/api/v1/auth/password")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("currentPassword", BENS_PASSWORD, "newPassword", "ein-neues-passwort"))
                .exchange()
                .expectStatus()
                .isNoContent();
        var annasNewPhone = Family.login(rest, "anna", "geheim-genug", "Annas neues Handy");

        rest.post()
                .uri("/api/v1/admin/backups/" + backup.get("id") + "/restore")
                .headers(annasNewPhone.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("password", Family.BACKUP_PASSWORD))
                .exchange()
                .expectStatus()
                .isOk();

        rest.get().uri("/api/v1/devices").headers(stolenLaptop.auth()).exchange().expectStatus().isUnauthorized();
        assertThat(login("ben", BENS_PASSWORD, "192.168.1.35")).as("old password").isEqualTo(401);
        assertThat(login("ben", "ein-neues-passwort", "192.168.1.35")).as("new password").isEqualTo(200);
        rest.get().uri("/api/v1/devices").headers(ben.auth()).exchange().expectStatus().isOk();
        rest.get().uri("/api/v1/devices").headers(annasNewPhone.auth()).exchange().expectStatus().isOk();
    }

    // --- A fresh server --------------------------------------------------------------

    /**
     * Without the setup code from the server's log, nobody claims a fresh server.
     * The family is set up in {@link #family()}; this empties it again first.
     */
    @Test
    void aStrangerCannotClaimAFreshServer() {
        String tables = db.meta().getTables().stream()
                .filter(table -> table.getSchema() != null && "public".equals(table.getSchema().getName()))
                .map(org.jooq.Named::getName)
                .filter(name -> !List.of("flyway_schema_history", "change_sequence", "entity_key_counter").contains(name))
                .distinct()
                .map(name -> "\"" + name + "\"")
                .collect(java.util.stream.Collectors.joining(", "));
        db.execute("truncate table " + tables + " cascade");

        assertThat(setUp(null)).as("without a code").isEqualTo(403);
        assertThat(setUp("WRON-GCOD")).as("with a wrong code").isEqualTo(403);
        assertThat(setUp("test-code")).as("with the code, typed in lower case").isEqualTo(201);
    }

    private int setUp(String code) {
        var body = new java.util.HashMap<String, Object>(Map.of(
                "familyName", "Fremde Familie",
                "timezone", "Europe/Berlin",
                "admin", Map.of("displayName", "Mallory", "username", "mallory", "password", "lang-genug-1"),
                "device", Map.of("deviceName", "Mallorys Laptop", "platform", "WEB"),
                "backupPassword", "ein-backup-passwort"));
        if (code != null) {
            body.put("setupCode", code);
        }
        return rest.post()
                .uri("/api/v1/setup")
                .header("X-Forwarded-For", "203.0.113.13")
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .exchange()
                .returnResult(Map.class)
                .getStatus()
                .value();
    }

    // --- The scheme in the invitation link -------------------------------------

    /** A server reached over TLS puts {@code https://} into the QR's deep link. */
    @Test
    void theInvitationLinkCarriesTheScheme() {
        var overTls = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .header("X-Forwarded-Proto", "https")
                .header("X-Forwarded-Host", "nas.example:8443")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((String) overTls.get("deepLink"))
                .startsWith("hiwiski://invite?host=https%3A%2F%2Fnas.example%3A8443&code=");

        assertThat((String) createInvitation().get("deepLink")).startsWith("hiwiski://invite?host=http%3A%2F%2F");
    }

    // --- Someone else's installation id ------------------------------------------

    /** Signing in with another member's installation id does not sign them out. */
    @Test
    void aForeignInstallationIdDoesNotSignAnotherMemberOut() {
        UUID installation = UUID.randomUUID();
        var bensLaptop = Family.login(rest, "ben", BENS_PASSWORD, Map.of(
                "deviceName", "Bens Laptop", "platform", "WEB", "installationId", installation.toString()));

        Family.login(rest, "anna", "geheim-genug", Map.of(
                "deviceName", "Annas Laptop", "platform", "WEB", "installationId", installation.toString()));

        rest.get().uri("/api/v1/devices").headers(bensLaptop.auth()).exchange().expectStatus().isOk();

        // The same member signing in again from it still replaces the earlier device.
        Family.login(rest, "ben", BENS_PASSWORD, Map.of(
                "deviceName", "Bens Laptop", "platform", "WEB", "installationId", installation.toString()));
        rest.get().uri("/api/v1/devices").headers(bensLaptop.auth()).exchange().expectStatus().isUnauthorized();
    }

    // --- Helpers -----------------------------------------------------------------------

    private Map<String, Object> createInvitation() {
        return rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    private int login(String username, String password, String clientAddress) {
        return login(username, password, clientAddress, null);
    }

    private int login(String username, String password, String clientAddress, String installationId) {
        Map<String, Object> device = new java.util.HashMap<>(Map.of("deviceName", "Probe", "platform", "ANDROID"));
        if (installationId != null) {
            device.put("installationId", installationId);
        }
        return rest.post()
                .uri("/api/v1/auth/login")
                .header("X-Forwarded-For", clientAddress)
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "username", username,
                        "password", password,
                        "device", device))
                .exchange()
                .returnResult(Map.class)
                .getStatus()
                .value();
    }

    private Family.Session invite(String displayName, String username, List<String> groupIds) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24", "groupIds", groupIds))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", displayName,
                        "username", username,
                        "password", BENS_PASSWORD,
                        "device", Map.of("deviceName", displayName + "s Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
    }

    private UUID groupId(String name) {
        var groups = (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/groups")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("groups");
        return groups.stream()
                .filter(group -> name.equals(group.get("name")))
                .map(group -> UUID.fromString((String) group.get("id")))
                .findFirst()
                .orElseThrow();
    }
}
