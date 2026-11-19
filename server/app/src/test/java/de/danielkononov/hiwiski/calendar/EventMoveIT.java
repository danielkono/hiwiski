package de.danielkononov.hiwiski.calendar;

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

/** An event moves to another calendar through its {@code calendarId}. */
@IntegrationTest
@SuppressWarnings("unchecked")
class EventMoveIT {

    @Autowired RestTestClient rest;

    @Test
    void anEventMovesToAnotherCalendar() {
        var device = new SyncClient(rest, Family.setUp(rest));
        UUID family = calendar(device, "Family");
        UUID work = calendar(device, "Work");
        UUID event = UUID.randomUUID();
        var created = device.push(SyncClient.withContainer(
                SyncClient.mutation(
                        "EVENT",
                        event,
                        null,
                        Map.of("title", "Dentist", "timeForm", "TIMED", "startsAt", "2026-10-12T08:00:00Z")),
                "CALENDAR",
                family));
        assertThat(created).allMatch(r -> "applied".equals(r.get("status")));

        var moved = device.push(SyncClient.mutation(
                "EVENT",
                event,
                ((Number) created.getFirst().get("version")).longValue(),
                Map.of("calendarId", work.toString())));

        assertThat(moved).allMatch(r -> "applied".equals(r.get("status")));
        assertThat(device.pullAll())
                .filteredOn(c -> event.toString().equals(c.get("entityId")))
                .last()
                .satisfies(c -> assertThat(c.get("containerId")).isEqualTo(work.toString()));
    }

    @Test
    void anEventDoesNotLeaveAllCalendars() {
        var device = new SyncClient(rest, Family.setUp(rest));
        UUID family = calendar(device, "Family");
        UUID event = UUID.randomUUID();
        var created = device.push(SyncClient.withContainer(
                SyncClient.mutation("EVENT", event, null, Map.of("title", "Dentist", "timeForm", "TIMED", "startsAt", "2026-11-16T10:00:00Z")),
                "CALENDAR",
                family));
        var none = new HashMap<String, Object>();
        none.put("calendarId", null);

        var moved = device.push(SyncClient.mutation(
                "EVENT", event, ((Number) created.getFirst().get("version")).longValue(), none));

        assertThat(moved).noneMatch(r -> "applied".equals(r.get("status")));
    }

    private static UUID calendar(SyncClient device, String name) {
        UUID id = UUID.randomUUID();
        List<Map<String, Object>> result = device.push(SyncClient.mutation(
                "CALENDAR", id, null, Map.of("name", name, "colorToken", "BLUE", "kind", "LOCAL")));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));
        return id;
    }
}
