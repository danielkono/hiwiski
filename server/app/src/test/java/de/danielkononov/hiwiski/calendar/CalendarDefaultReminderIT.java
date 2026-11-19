package de.danielkononov.hiwiski.calendar;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/** A calendar's default reminder travels with the calendar; the app applies it. */
@IntegrationTest
class CalendarDefaultReminderIT {

    @Autowired RestTestClient rest;

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void theDefaultReminderIsSyncedAndCanBeCleared() {
        var device = new SyncClient(rest, Family.setUp(rest));
        UUID calendar = UUID.randomUUID();

        var created = device.push(SyncClient.mutation(
                "CALENDAR",
                calendar,
                null,
                Map.of("name", "Familie", "colorToken", "BLUE", "kind", "LOCAL", "defaultReminderMinutes", 30)));
        assertThat(created).allMatch(r -> "applied".equals(r.get("status")));
        assertThat(device.pullAll())
                .anyMatch(c -> calendar.toString().equals(c.get("entityId"))
                        && Integer.valueOf(30).equals(((Map) c.get("fields")).get("defaultReminderMinutes")));

        var none = new HashMap<String, Object>();
        none.put("defaultReminderMinutes", null);
        var cleared = device.push(SyncClient.mutation(
                "CALENDAR", calendar, ((Number) created.getFirst().get("version")).longValue(), none));
        assertThat(cleared).allMatch(r -> "applied".equals(r.get("status")));
        assertThat(device.pullAll())
                .anyMatch(c -> calendar.toString().equals(c.get("entityId"))
                        && ((Map) c.get("fields")).containsKey("defaultReminderMinutes")
                        && ((Map) c.get("fields")).get("defaultReminderMinutes") == null);
    }
}
