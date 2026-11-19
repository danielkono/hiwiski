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
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Values the devices cannot read are refused where they come in.
 *
 * <p>What one member's device writes into a shared list or calendar, every other
 * member's device has to read. Each of these was answered "applied" and stored.
 */
@IntegrationTest
// `push` takes its mutations as varargs of a generic map.
@SuppressWarnings("unchecked")
class FieldValuesIT {

    @Autowired RestTestClient rest;

    private SyncClient device;
    private UUID list;
    private UUID calendar;

    @BeforeEach
    void aListAndACalendar() {
        device = new SyncClient(rest, Family.setUp(rest));
        list = UUID.randomUUID();
        calendar = UUID.randomUUID();
        device.push(SyncClient.mutation("TODO_LIST", list, null, Map.of("name", "Haushalt", "kind", "STANDARD")));
        device.push(SyncClient.mutation("CALENDAR", calendar, null, Map.of("name", "Familie", "kind", "LOCAL")));
    }

    private Map<String, Object> task(Map<String, Object> fields) {
        Map<String, Object> all = new LinkedHashMap<>(Map.of("title", "Müll", "status", "OPEN"));
        all.putAll(fields);
        return device.push(SyncClient.withContainer(
                        SyncClient.mutation("TODO", UUID.randomUUID(), null, all), "TODO_LIST", list))
                .getFirst();
    }

    private Map<String, Object> event(Map<String, Object> fields) {
        Map<String, Object> all = new LinkedHashMap<>(Map.of("title", "Zahnarzt"));
        all.putAll(fields);
        return device.push(SyncClient.withContainer(
                        SyncClient.mutation("EVENT", UUID.randomUUID(), null, all), "CALENDAR", calendar))
                .getFirst();
    }

    private static void refused(Map<String, Object> result) {
        assertThat(result.get("status")).isEqualTo("rejected");
        assertThat(result.get("code")).isEqualTo("sync.invalid_field");
    }

    @Test
    void aTaskHasAStatusTheDevicesKnow() {
        refused(task(Map.of("status", "MAYBE")));
        assertThat(task(Map.of("status", "DONE")).get("status")).isEqualTo("applied");
    }

    /** As for an event: with an interval of 0 the devices' library never returns. */
    @Test
    void aTaskRepeatsOnlyByARuleTheDevicesExpand() {
        refused(task(Map.of("dueDate", "2026-11-16", "rrule", "FREQ=WEEKLY;INTERVAL=0;BYDAY=MO")));
        refused(task(Map.of("dueDate", "2026-11-16", "rrule", "FREQ=NEVER")));
        assertThat(task(Map.of("dueDate", "2026-11-16", "rrule", "FREQ=WEEKLY;BYDAY=MO")).get("status"))
                .isEqualTo("applied");
    }

    @Test
    void anEventDoesNotRepeatWithAnIntervalOfZero() {
        refused(event(Map.of(
                "timeForm", "RECURRING",
                "localStart", "2026-11-16T08:00",
                "localEnd", "2026-11-16T09:00",
                "timeZone", "Europe/Berlin",
                "rrule", "FREQ=DAILY;INTERVAL=0")));
    }

    @Test
    void aNewEventHasTheStartOfItsForm() {
        refused(event(Map.of("timeForm", "TIMED")));
        refused(event(Map.of("timeForm", "ALL_DAY")));
        assertThat(event(Map.of("timeForm", "ALL_DAY", "startDate", "2026-11-16", "endDate", "2026-11-16"))
                        .get("status"))
                .isEqualTo("applied");
    }

    @Test
    void anEventDoesNotEndBeforeItStarts() {
        refused(event(Map.of("timeForm", "ALL_DAY", "startDate", "2026-11-16", "endDate", "2026-11-01")));
        refused(event(Map.of(
                "timeForm", "TIMED", "startsAt", "2026-11-16T10:00:00Z", "endsAt", "2026-11-16T09:00:00Z")));
        assertThat(event(Map.of(
                                "timeForm", "TIMED",
                                "startsAt", "2026-11-16T10:00:00+01:00",
                                "endsAt", "2026-11-16T09:30:00Z"))
                        .get("status"))
                .isEqualTo("applied");
    }

    /** Cut to fit, 99999999999999999999 was stored as 1661992959 and answered "applied". */
    @Test
    void aNumberThatDoesNotFitIsRefused() {
        var tooLarge = device.push(SyncClient.mutation(
                        "WIKI_PAGE",
                        UUID.randomUUID(),
                        null,
                        Map.of(
                                "title", "Seite",
                                "content", "",
                                "kind", "PAGE",
                                "position", new java.math.BigInteger("99999999999999999999"))))
                .getFirst();
        var broken = device.push(SyncClient.mutation(
                        "WIKI_PAGE",
                        UUID.randomUUID(),
                        null,
                        Map.of("title", "Seite", "content", "", "kind", "PAGE", "position", 1.5)))
                .getFirst();

        refused(tooLarge);
        refused(broken);
    }
}
