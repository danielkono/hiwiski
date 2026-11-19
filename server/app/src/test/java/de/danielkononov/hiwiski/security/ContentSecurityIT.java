package de.danielkononov.hiwiski.security;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Content that other members' calendars and feeds take as it is.
 *
 * <p>The rule, the zone, the local times and the
 * exception keys of an event went into every subscriber's ICS feed verbatim.
 */
@IntegrationTest
class ContentSecurityIT {

    private static final String FORGED = "\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:forged@hiwiski\r\nSUMMARY:Pickup moved";

    @Autowired RestTestClient rest;

    @Test
    void aRuleWithContentLinesOfItsOwnIsRefused() {
        assertThat(push(series(Map.of("rrule", "FREQ=DAILY" + FORGED)))).isEqualTo("rejected");
    }

    @Test
    void aZoneWithContentLinesOfItsOwnIsRefused() {
        assertThat(push(series(Map.of("timeZone", "Europe/Berlin" + FORGED)))).isEqualTo("rejected");
    }

    @Test
    void aLocalStartWithContentLinesOfItsOwnIsRefused() {
        assertThat(push(series(Map.of("localStart", "2026-10-05T16:00" + FORGED)))).isEqualTo("rejected");
    }

    @Test
    void anExceptionKeyWithContentLinesOfItsOwnIsRefused() {
        Map<String, Object> exception = Map.of("2026-10-12T16:00" + FORGED, Map.of("cancelled", true));

        assertThat(push(series(Map.of("exceptions", exception)))).isEqualTo("rejected");
    }

    @Test
    void aMovedOccurrenceWithContentLinesOfItsOwnIsRefused() {
        Map<String, Object> exception =
                Map.of("2026-10-12T16:00", Map.of("start", "2026-10-12T17:00" + FORGED, "end", "2026-10-12T18:00"));

        assertThat(push(series(Map.of("exceptions", exception)))).isEqualTo("rejected");
    }

    @Test
    void aSecondlyRuleIsRefused() {
        assertThat(push(series(Map.of("rrule", "FREQ=SECONDLY")))).isEqualTo("rejected");
    }

    @Test
    void whatTheDevicesWriteStillGoesThrough() {
        Map<String, Object> exceptions = Map.of(
                "2026-10-12T16:00", Map.of("start", "2026-10-12T17:00", "end", "2026-10-12T18:00"),
                "2026-10-19T16:00", Map.of("cancelled", true));

        assertThat(push(series(Map.of(
                        "rrule", "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH;UNTIL=20271231T235959Z",
                        "exceptions", exceptions))))
                .isEqualTo("applied");
    }

    /** A weekly series as the app writes it, with [overrides] on top. */
    private static Map<String, Object> series(Map<String, Object> overrides) {
        Map<String, Object> fields = new HashMap<>(Map.of(
                "title", "Swimming",
                "timeForm", "RECURRING",
                "localStart", "2026-10-05T16:00",
                "localEnd", "2026-10-05T17:00",
                "timeZone", "Europe/Berlin",
                "rrule", "FREQ=WEEKLY"));
        fields.putAll(overrides);
        return fields;
    }

    @SuppressWarnings("unchecked")
    private String push(Map<String, Object> fields) {
        var device = new SyncClient(rest, Family.setUp(rest));
        UUID calendar = UUID.randomUUID();
        List<Map<String, Object>> created = device.push(SyncClient.mutation(
                "CALENDAR", calendar, null, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL")));
        assertThat(created).allMatch(r -> "applied".equals(r.get("status")));

        var result = device.push(SyncClient.withContainer(
                SyncClient.mutation("EVENT", UUID.randomUUID(), null, fields), "CALENDAR", calendar));
        return String.valueOf(result.getFirst().get("status"));
    }
}
