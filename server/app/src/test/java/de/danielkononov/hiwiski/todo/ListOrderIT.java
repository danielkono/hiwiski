package de.danielkononov.hiwiski.todo;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Each member sorts the task overview for themselves: the order reaches all of their
 * devices and nobody else's.
 */
@IntegrationTest
class ListOrderIT {

    private static final String LIST_ORDER = "LIST_ORDER";

    @Autowired RestTestClient rest;

    @Test
    void theOrderReachesTheMembersOtherDevicesAndNoOneElse() {
        var phone = Family.setUp(rest);
        var laptop = Family.login(rest, "anna", "geheim-genug", "Laptop");
        var ben = invite(phone);

        var list = UUID.randomUUID();
        var results = new SyncClient(rest, phone)
                .push(SyncClient.mutation(LIST_ORDER, phone.memberId(), null, Map.of("listIds", List.of(list.toString()))));
        assertThat(results).extracting(result -> result.get("status")).containsExactly("applied");

        assertThat(orders(new SyncClient(rest, laptop).pullAll()))
                .singleElement()
                .satisfies(change -> assertThat(fields(change).get("listIds")).isEqualTo(List.of(list.toString())));
        assertThat(orders(new SyncClient(rest, ben).pullAll())).isEmpty();
    }

    @Test
    void anotherMemberCannotChangeIt() {
        var anna = Family.setUp(rest);
        var ben = invite(anna);
        new SyncClient(rest, anna)
                .push(SyncClient.mutation(LIST_ORDER, anna.memberId(), null, Map.of("listIds", List.of())));

        var results = new SyncClient(rest, ben)
                .push(SyncClient.mutation(LIST_ORDER, anna.memberId(), 1L, Map.of("listIds", List.of("x"))));

        assertThat(results).extracting(result -> result.get("status")).containsExactly("rejected");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> fields(Map<String, Object> change) {
        return (Map<String, Object>) change.get("fields");
    }

    private static List<Map<String, Object>> orders(List<Map<String, Object>> changes) {
        return changes.stream().filter(change -> LIST_ORDER.equals(change.get("entityType"))).toList();
    }

    @SuppressWarnings("unchecked")
    private Family.Session invite(Family.Session admin) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(admin.auth())
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
                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(signedIn);
    }
}
