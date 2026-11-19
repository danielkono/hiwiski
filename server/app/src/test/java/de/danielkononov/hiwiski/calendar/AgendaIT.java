package de.danielkononov.hiwiski.calendar;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;
import org.springframework.web.util.UriBuilder;
import org.springframework.beans.factory.annotation.Autowired;

/**
 * The agenda a home screen widget reads while the app is closed: the coming occurrences
 * of the chosen calendars, expanded as the app expands them, and only what the caller
 * may see.
 */
@IntegrationTest
@SuppressWarnings("unchecked")
class AgendaIT {

    private static final String BERLIN = "Europe/Berlin";

    @Autowired RestTestClient rest;

    private Family.Session anna;
    private SyncClient phone;
    private LocalDate today;

    @BeforeEach
    void aFamily() {
        anna = Family.setUp(rest);
        phone = new SyncClient(rest, anna);
        today = LocalDate.now(ZoneId.of(BERLIN));
    }

    @Test
    void aSeriesComesExpandedWithItsExceptions() {
        UUID family = calendar(phone, "Family", "GREEN");
        UUID lesson = UUID.randomUUID();
        // Every day at 23:58, so that it is still ahead whenever the test runs; the
        // occurrence the day after tomorrow is cancelled, and the one tomorrow moved.
        String tomorrow = today.plusDays(1) + "T23:58";
        String dayAfter = today.plusDays(2) + "T23:58";
        event(phone, family, lesson, Map.of(
                "title", "Piano",
                "timeForm", "RECURRING",
                "localStart", today.minusDays(10) + "T23:58",
                "localEnd", today.minusDays(10) + "T23:59",
                "timeZone", BERLIN,
                "rrule", "FREQ=DAILY",
                "exceptions", Map.of(
                        tomorrow, Map.of("start", today.plusDays(1) + "T17:00", "end", today.plusDays(1) + "T18:00"),
                        dayAfter, Map.of("cancelled", true))));

        var agenda = agenda(anna, Map.of("days", "4", "timeZone", BERLIN), HttpStatus.OK);

        var occurrences = (List<Map<String, Object>>) agenda.get("occurrences");
        assertThat(occurrences)
                .extracting(o -> o.get("start"))
                .containsExactly(
                        today + "T23:58",
                        today.plusDays(1) + "T17:00",
                        today.plusDays(3) + "T23:58");
        assertThat(occurrences.get(1).get("moved")).isEqualTo(true);
        assertThat(occurrences.getFirst())
                .containsEntry("eventId", lesson.toString())
                .containsEntry("calendarId", family.toString())
                .containsEntry("title", "Piano")
                .containsEntry("colorToken", "GREEN")
                .containsEntry("allDay", false);
        assertThat(agenda.get("timeZone")).isEqualTo(BERLIN);
        assertThat(agenda.get("to")).isEqualTo(today.plusDays(4) + "T00:00");
        assertThat(((Number) agenda.get("position")).longValue()).isPositive();
        assertThat(agenda.get("truncated")).isEqualTo(false);
    }

    @Test
    void onlyTheChosenCalendarsAndWhatIsNotOver() {
        UUID family = calendar(phone, "Family", "BLUE");
        UUID work = calendar(phone, "Work", "RUST");
        event(phone, family, UUID.randomUUID(), Map.of(
                "title", "Holidays",
                "timeForm", "ALL_DAY",
                // Began before the window and still runs.
                "startDate", today.minusDays(3).toString(),
                "endDate", today.plusDays(1).toString()));
        event(phone, family, UUID.randomUUID(), Map.of(
                "title", "Over",
                "timeForm", "ALL_DAY",
                "startDate", today.minusDays(5).toString(),
                "endDate", today.minusDays(4).toString()));
        event(phone, family, UUID.randomUUID(), Map.of(
                "title", "Far ahead",
                "timeForm", "ALL_DAY",
                "startDate", today.plusDays(30).toString()));
        event(phone, work, UUID.randomUUID(), Map.of(
                "title", "Meeting",
                "timeForm", "ALL_DAY",
                "startDate", today.plusDays(1).toString()));

        var agenda = agenda(
                anna, Map.of("calendarIds", family.toString(), "days", "7", "timeZone", BERLIN), HttpStatus.OK);

        assertThat((List<Map<String, Object>>) agenda.get("occurrences"))
                .extracting(o -> o.get("title"))
                .containsExactly("Holidays");
        assertThat((List<Map<String, Object>>) agenda.get("occurrences"))
                .first()
                .satisfies(o -> {
                    assertThat(o.get("start")).isEqualTo(today.minusDays(3) + "T00:00");
                    assertThat(o.get("end")).isEqualTo(today.plusDays(1) + "T00:00");
                    assertThat(o.get("allDay")).isEqualTo(true);
                });
    }

    @Test
    void aCalendarNotSharedIsNotThere() {
        UUID private_ = calendar(phone, "Anna only", "PINK");
        event(phone, private_, UUID.randomUUID(), Map.of(
                "title", "Secret", "timeForm", "ALL_DAY", "startDate", today.plusDays(1).toString()));
        var ben = invite("Ben", "ben");

        // Asked for by id it answers as if there were nothing -- not a 403 that would
        // confirm the calendar exists.
        var asked = agenda(ben, Map.of("calendarIds", private_.toString(), "timeZone", BERLIN), HttpStatus.OK);
        var all = agenda(ben, Map.of("timeZone", BERLIN), HttpStatus.OK);

        assertThat((List<?>) asked.get("occurrences")).isEmpty();
        assertThat((List<?>) all.get("occurrences")).isEmpty();
    }

    @Test
    void aSharedCalendarIsThere() {
        UUID family = calendar(phone, "Family", "TEAL");
        event(phone, family, UUID.randomUUID(), Map.of(
                "title", "Dentist", "timeForm", "ALL_DAY", "startDate", today.plusDays(1).toString()));
        var ben = invite("Ben", "ben");
        share(anna, "CALENDAR", family, ben, "READ");

        var agenda = agenda(ben, Map.of("timeZone", BERLIN), HttpStatus.OK);

        assertThat((List<Map<String, Object>>) agenda.get("occurrences"))
                .extracting(o -> o.get("title"))
                .containsExactly("Dentist");
    }

    @Test
    void theLimitCutsAndSaysSo() {
        UUID family = calendar(phone, "Family", "BLUE");
        for (int day = 1; day <= 3; day++) {
            event(phone, family, UUID.randomUUID(), Map.of(
                    "title", "Day " + day, "timeForm", "ALL_DAY", "startDate", today.plusDays(day).toString()));
        }

        var agenda = agenda(anna, Map.of("limit", "2", "timeZone", BERLIN), HttpStatus.OK);

        assertThat((List<Map<String, Object>>) agenda.get("occurrences"))
                .extracting(o -> o.get("title"))
                .containsExactly("Day 1", "Day 2");
        assertThat(agenda.get("truncated")).isEqualTo(true);
    }

    @Test
    void anUnknownZoneIsRefused() {
        var error = agenda(anna, Map.of("timeZone", "Mars/Olympus"), HttpStatus.BAD_REQUEST);

        assertThat(error.get("code")).isEqualTo("calendar.time_zone_invalid");
    }

    @Test
    void notWithoutASignIn() {
        rest.get().uri("/api/v1/calendar/agenda").exchange().expectStatus().isUnauthorized();
    }

    private Map<String, Object> agenda(Family.Session who, Map<String, String> query, HttpStatus status) {
        return rest.get()
                .uri(builder -> withQuery(builder.path("/api/v1/calendar/agenda"), query).build())
                .headers(who.auth())
                .exchange()
                .expectStatus()
                .isEqualTo(status)
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    private static UriBuilder withQuery(UriBuilder builder, Map<String, String> query) {
        query.forEach(builder::queryParam);
        return builder;
    }

    private static UUID calendar(SyncClient device, String name, String color) {
        UUID id = UUID.randomUUID();
        var result = device.push(SyncClient.mutation(
                "CALENDAR", id, null, Map.of("name", name, "colorToken", color, "kind", "LOCAL")));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));
        return id;
    }

    private static void event(SyncClient device, UUID calendar, UUID id, Map<String, Object> fields) {
        var result = device.push(SyncClient.withContainer(
                SyncClient.mutation("EVENT", id, null, fields), "CALENDAR", calendar));
        assertThat(result).allMatch(r -> "applied".equals(r.get("status")));
    }

    private void share(Family.Session owner, String type, UUID id, Family.Session with, String level) {
        rest.put()
                .uri("/api/v1/items/" + type + "/" + id + "/shares")
                .headers(owner.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", with.memberId().toString(), "level", level))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    private Family.Session invite(String displayName, String username) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24", "groupIds", List.of()))
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
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", displayName + "s Phone", "platform", "IOS")))
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
    }
}
