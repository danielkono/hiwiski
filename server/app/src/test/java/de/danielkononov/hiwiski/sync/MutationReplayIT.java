package de.danielkononov.hiwiski.sync;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * A mutation sent again under its id.
 *
 * <p>The answer to a resend is the one the mutation got the first time -- for the member
 * who sent it, about the item it was about. Looked up by the id alone, the stored answer
 * went to whoever sent the id, and a conflict's values were read for whatever item the
 * resend named: past the visibility check, a board's address included.
 */
@IntegrationTest
// `push` takes its mutations as varargs of a generic map.
@SuppressWarnings("unchecked")
class MutationReplayIT {

    private static final String PAGE = "WIKI_PAGE";
    private static final String BOARD = "BOARD";
    private static final String ANNAS_ADDRESS = "Qm7xK2pLw9ZtR4vYc8NbH3sDf6GjU1aEoXiT5yPq";

    @Autowired RestTestClient rest;

    private SyncClient anna;
    private SyncClient bensPhone;
    private SyncClient bensLaptop;

    @BeforeEach
    void familyWithTwoMembers() {
        var annasSession = Family.setUp(rest);
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(annasSession.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var signedIn = rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", "ben",
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Bens Handy", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        anna = new SyncClient(rest, annasSession);
        bensPhone = new SyncClient(rest, Family.toSession(signedIn));
        bensLaptop = new SyncClient(rest, Family.login(rest, "ben", "bens-langes-passwort", "Bens Laptop"));
    }

    /** A conflict of Ben's own: the laptop changed the fields, the phone still builds on the old version. */
    private Map<String, Object> conflictOfBens(String type, Map<String, Object> created, Map<String, Object> changed) {
        UUID own = UUID.randomUUID();
        long version = ((Number) bensPhone.push(SyncClient.mutation(type, own, null, created))
                        .getFirst()
                        .get("version"))
                .longValue();
        bensLaptop.push(SyncClient.mutation(type, own, version, changed));
        var stale = SyncClient.mutation(type, own, version, changed);
        assertThat(bensPhone.push(stale).getFirst().get("status")).isEqualTo("conflict");
        return stale;
    }

    private static Map<String, Object> about(Map<String, Object> mutation, UUID otherItem) {
        Map<String, Object> resent = new LinkedHashMap<>(mutation);
        resent.put("entityId", otherItem.toString());
        return resent;
    }

    @Test
    void aConflictResentAboutSomeoneElsesPageShowsNothingOfIt() {
        UUID diary = UUID.randomUUID();
        anna.push(SyncClient.mutation(
                PAGE, diary, null, Map.of("title", "Tagebuch", "content", "nur für Anna", "kind", "PAGE")));
        var conflict = conflictOfBens(
                PAGE,
                Map.of("title", "Notizen", "content", "eins", "kind", "PAGE"),
                Map.of("title", "Notizen 2", "content", "zwei"));

        var answer = bensPhone.push(about(conflict, diary)).getFirst();

        assertThat(answer.get("status")).isEqualTo("rejected");
        assertThat(answer.get("code")).isEqualTo("sync.mutation_id_reused");
        assertThat(String.valueOf(answer)).doesNotContain("nur für Anna").doesNotContain("Tagebuch");
    }

    @Test
    void aConflictResentAboutSomeoneElsesBoardDoesNotGiveItsAddress() {
        UUID annasBoard = UUID.randomUUID();
        assertThat(anna.push(SyncClient.mutation(
                                BOARD,
                                annasBoard,
                                null,
                                Map.of("kind", "DASHBOARD", "name", "Flur", "layout", "GRID", "token", ANNAS_ADDRESS)))
                        .getFirst()
                        .get("status"))
                .isEqualTo("applied");
        var conflict = conflictOfBens(
                BOARD,
                Map.of("kind", "DASHBOARD", "name", "Küche", "layout", "GRID", "token", "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8"),
                Map.of("token", "z9Y8x7W6v5U4t3S2r1Q0p9O8n7M6l5K4j3I2"));

        var answer = bensPhone.push(about(conflict, annasBoard)).getFirst();

        assertThat(answer.get("status")).isEqualTo("rejected");
        assertThat(String.valueOf(answer)).doesNotContain(ANNAS_ADDRESS);
    }

    /** The honest resend still gets its conflict, with today's values. */
    @Test
    void aConflictResentAsItWasIsAConflictAgain() {
        var conflict = conflictOfBens(
                PAGE,
                Map.of("title", "Notizen", "content", "eins", "kind", "PAGE"),
                Map.of("title", "Notizen 2", "content", "zwei"));

        var answer = bensPhone.push(conflict).getFirst();

        assertThat(answer.get("status")).isEqualTo("conflict");
        assertThat(((Map<?, ?>) answer.get("serverFields")).get("content")).isEqualTo("zwei");
    }

    /**
     * Another member's mutation id is not answered with that member's result: Ben got
     * "duplicate" and Anna's item id, and his own change was dropped without a word.
     */
    @Test
    void anotherMembersMutationIdIsRefused() {
        var annas = SyncClient.mutation(
                PAGE, UUID.randomUUID(), null, Map.of("title", "Annas", "content", "", "kind", "PAGE"));
        anna.push(annas);
        var bens = SyncClient.mutation(
                PAGE, UUID.randomUUID(), null, Map.of("title", "Bens", "content", "", "kind", "PAGE"));
        bens.put("mutationId", annas.get("mutationId"));

        var answer = bensPhone.push(bens).getFirst();

        assertThat(answer.get("status")).isEqualTo("rejected");
        assertThat(answer.get("entityId")).isEqualTo(bens.get("entityId"));
    }

    /** What idempotency is for: the same mutation from the same member, once more. */
    @Test
    void theSameMutationSentTwiceIsADuplicate() {
        var mutation = SyncClient.mutation(
                PAGE, UUID.randomUUID(), null, Map.of("title", "Einmal", "content", "", "kind", "PAGE"));
        assertThat(bensPhone.push(mutation).getFirst().get("status")).isEqualTo("applied");

        // From the laptop too: after a new sign-in the outbox goes out under a new device.
        assertThat(bensLaptop.push(mutation).getFirst().get("status")).isEqualTo("duplicate");
    }
}
