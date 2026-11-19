package de.danielkononov.hiwiski.identity;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

@IntegrationTest
class InvitationIT {

    @Autowired RestTestClient rest;

    private Map<?, ?> invite(Family.Session admin, String displayName) {
        return rest.post()
                .uri("/api/v1/invitations")
                .headers(admin.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("displayName", displayName, "validity", "HOURS_24"))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    @Test
    void theCodeHasNoConfusableCharactersAndTheQrCarriesTheDeepLink() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");

        String code = (String) invitation.get("code");
        assertThat(code).hasSize(7);
        // It gets read aloud and copied by hand: no 0 next to O, no 1 next to I and L.
        assertThat(code).doesNotContain("0", "O", "1", "I", "L");
        assertThat((String) invitation.get("deepLink")).startsWith("hiwiski://invite?host=");
        assertThat((String) invitation.get("deepLink")).contains("code=" + code);
    }

    @Test
    void thePreviewTellsWhereYouAreJoiningWithoutSigningIn() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");

        // Without this card nobody knows what they are joining.
        rest.get()
                .uri("/api/v1/invitations/" + invitation.get("code"))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.familyName")
                .isEqualTo("Familie Probe")
                .jsonPath("$.invitedBy")
                .isEqualTo("Anna")
                .jsonPath("$.displayName")
                .isEqualTo("Ben");
    }

    @Test
    void aMadeUpCodeLooksLikeAnExpiredOne() {
        Family.setUp(rest);
        rest.get()
                .uri("/api/v1/invitations/XXXXXXX")
                .exchange()
                .expectStatus()
                .isNotFound()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.invitation_not_found");
    }

    @Test
    void joiningSignsInRightAwayAndSetsTheGroups() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");

        var signedIn =
                rest.post()
                        .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(
                                Map.of(
                                        "displayName", "Ben",
                                        "username", "ben",
                                        "password", "bens-langes-passwort",
                                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                        .exchange()
                        .expectStatus()
                        .isCreated()
                        .expectBody(Map.class)
                        .returnResult()
                        .getResponseBody();

        var ben = Family.toSession(signedIn);
        rest.get()
                .uri("/api/v1/auth/session")
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.member.displayName")
                .isEqualTo("Ben")
                .jsonPath("$.member.isAdmin")
                .isEqualTo(false)
                // Every new member goes into the first group -- otherwise every share
                // with "Everyone" would pass them by.
                .jsonPath("$.member.groupIds.length()")
                .isEqualTo(1);
    }

    @Test
    void aCodeCanBeRedeemedOnlyOnce() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        String code = (String) invitation.get("code");

        rest.post()
                .uri("/api/v1/invitations/" + code + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "displayName", "Ben",
                                "username", "ben",
                                "password", "bens-langes-passwort",
                                "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .isCreated();

        // Used up looks like made up: 404, not 409 -- otherwise the difference would
        // reveal that the code existed.
        rest.post()
                .uri("/api/v1/invitations/" + code + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "displayName", "Second",
                                "username", "second",
                                "password", "noch-ein-passwort",
                                "device", Map.of("deviceName", "Stranger", "platform", "WEB")))
                .exchange()
                .expectStatus()
                .isNotFound();
    }

    @Test
    void onlyTheAdministratorInvites() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "displayName", "Ben",
                                "username", "ben",
                                "password", "bens-langes-passwort",
                                "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .isCreated();

        var ben = Family.login(rest, "ben", "bens-langes-passwort", "Bens Laptop");
        rest.post()
                .uri("/api/v1/invitations")
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectStatus()
                .isForbidden()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.admin_required");
    }

    /**
     * "Everyone" stays the default however the groups are ordered -- and cannot be
     * deleted, or a share with it would pass every future member by.
     */
    @Test
    @SuppressWarnings("unchecked")
    void newMembersJoinTheGroupTheSetupNamed() {
        var admin = Family.setUp(rest);
        List<Map<String, Object>> groups = rest.get()
                .uri("/api/v1/groups")
                .headers(admin.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("groups") instanceof List<?> list ? (List<Map<String, Object>>) list : List.of();
        String everyone = groups.stream()
                .filter(group -> "Everyone".equals(group.get("name")))
                .map(group -> (String) group.get("id"))
                .findFirst()
                .orElseThrow();

        rest.delete()
                .uri("/api/v1/groups/" + everyone)
                .headers(admin.auth())
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.group_default");
    }

    /** An invitation into a group deleted since still lets the person in. */
    @Test
    @SuppressWarnings("unchecked")
    void aDeletedGroupDoesNotBlockTheInvitation() {
        var admin = Family.setUp(rest);
        var group = (Map<String, Object>) rest.post()
                .uri("/api/v1/groups")
                .headers(admin.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "Grandparents", "memberIds", List.of()))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(admin.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("displayName", "Opa", "validity", "HOURS_24", "groupIds", List.of(group.get("id"))))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        rest.delete().uri("/api/v1/groups/" + group.get("id")).headers(admin.auth()).exchange().expectStatus()
                .is2xxSuccessful();

        rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Opa",
                        "username", "opa",
                        "password", "opas-langes-passwort",
                        "device", Map.of("deviceName", "Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .isCreated();
    }

    /** A group's members have to exist -- an unknown ID is a 400, not a server error. */
    @Test
    void aGroupWithAnUnknownMemberIsRefused() {
        var admin = Family.setUp(rest);
        rest.post()
                .uri("/api/v1/groups")
                .headers(admin.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "Ghosts", "memberIds", List.of(java.util.UUID.randomUUID().toString())))
                .exchange()
                .expectStatus()
                .isBadRequest();
    }

    /** For one handed to the wrong person: withdrawn, its code opens nothing. */
    @Test
    @SuppressWarnings("unchecked")
    void aWithdrawnInvitationOpensNothing() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        var other = invite(admin, "Clara");

        revoke(admin, invitation).expectStatus().isNoContent();

        rest.get()
                .uri("/api/v1/invitations/" + invitation.get("code"))
                .exchange()
                .expectStatus()
                .isNotFound()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.invitation_not_found");
        redeem((String) invitation.get("code"), UUID.randomUUID()).expectStatus().isNotFound();
        var open = (List<Map<String, Object>>) rest.get()
                .uri("/api/v1/invitations")
                .headers(admin.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("invitations");
        assertThat(open).extracting(row -> row.get("id")).containsExactly(other.get("id"));

        // Withdrawn twice: there is no open invitation left to withdraw.
        revoke(admin, invitation)
                .expectStatus()
                .isNotFound()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.invitation_not_found");
    }

    /** A redeemed invitation stays the record of who joined with it. */
    @Test
    void aRedeemedInvitationCannotBeWithdrawn() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        redeem((String) invitation.get("code"), UUID.randomUUID()).expectStatus().isCreated();

        revoke(admin, invitation)
                .expectStatus()
                .isNotFound()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.invitation_not_found");
        Family.login(rest, "ben", "bens-langes-passwort", "Bens Laptop");
    }

    @Test
    void onlyTheAdministratorWithdraws() {
        var admin = Family.setUp(rest);
        redeem((String) invite(admin, "Ben").get("code"), UUID.randomUUID()).expectStatus().isCreated();
        var ben = Family.login(rest, "ben", "bens-langes-passwort", "Bens Laptop");
        var invitation = invite(admin, "Clara");

        revoke(ben, invitation)
                .expectStatus()
                .isForbidden()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.admin_required");
        // Its path sits next to the redemption, which needs no sign-in; this one does.
        rest.post()
                .uri("/api/v1/invitations/" + invitation.get("id") + "/revoke")
                .exchange()
                .expectStatus()
                .isUnauthorized();
        rest.get().uri("/api/v1/invitations/" + invitation.get("code")).exchange().expectStatus().isOk();
    }

    private RestTestClient.ResponseSpec revoke(Family.Session session, Map<?, ?> invitation) {
        return rest.post()
                .uri("/api/v1/invitations/" + invitation.get("id") + "/revoke")
                .headers(session.auth())
                .exchange();
    }

    /** The id a device brings that was used without a server. */
    @Test
    void aJoiningMemberKeepsTheIdTheAppBrings() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        var id = UUID.randomUUID();

        var signedIn = redeem((String) invitation.get("code"), id)
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        assertThat(Family.toSession(signedIn).memberId()).isEqualTo(id);
    }

    /**
     * Someone else's id is refused, and the invitation stays usable: the device can
     * still join under an id of the server's.
     */
    @Test
    void anIdTakenAlreadyIsRefused() {
        var admin = Family.setUp(rest);
        var invitation = invite(admin, "Ben");
        String code = (String) invitation.get("code");

        redeem(code, admin.memberId())
                .expectStatus()
                .isEqualTo(409)
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("identity.id_taken");

        redeem(code, UUID.randomUUID()).expectStatus().isCreated();
    }

    private RestTestClient.ResponseSpec redeem(String code, UUID memberId) {
        return rest.post()
                .uri("/api/v1/invitations/" + code + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(
                        Map.of(
                                "memberId", memberId.toString(),
                                "displayName", "Ben",
                                "username", "ben",
                                "password", "bens-langes-passwort",
                                "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange();
    }
}
