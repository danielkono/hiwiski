package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.internal.RecurrenceTestAccess;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.ObjectMapper;

/**
 * The expansion of whole events against {@code golden/occurrences.json}.
 *
 * <p>The app checks the same file with its {@code EventExpander}. The widget's agenda is
 * expanded here while the app is closed; whatever the two disagree on, a family would
 * see as a different calendar on the home screen than in the app.
 *
 * <p>TIMED cases are instants: their window and their results are in UTC, with a
 * {@code Z}, and read in UTC here.
 */
class OccurrencesGoldenTest {

    private static final DateTimeFormatter LOCAL = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    private static final Path GOLDEN = Path.of("../../golden/occurrences.json");

    @SuppressWarnings("unchecked")
    @TestFactory
    Stream<DynamicTest> everyCaseFromTheGoldenFile() throws Exception {
        var occurrences = new EventOccurrences(RecurrenceTestAccess.create());
        Map<String, Object> document = new ObjectMapper().readValue(Files.readString(GOLDEN), Map.class);
        List<Map<String, Object>> cases = (List<Map<String, Object>>) document.get("cases");

        assertThat(cases).isNotEmpty();

        return cases.stream().map(testCase -> DynamicTest.dynamicTest(
                String.valueOf(testCase.get("name")),
                () -> {
                    var fields = (Map<String, Object>) testCase.get("event");
                    boolean timed = EventOccurrences.TIMED.equals(fields.get("timeForm"));

                    var actual = occurrences.expand(
                            times(fields),
                            local((String) testCase.get("from")),
                            local((String) testCase.get("to")),
                            ZoneOffset.UTC);

                    var shown = actual.stream()
                            .map(item -> {
                                Map<String, Object> row = new LinkedHashMap<>();
                                row.put("start", format(item.start(), timed));
                                row.put("end", format(item.end(), timed));
                                row.put("allDay", item.allDay());
                                row.put("moved", item.moved());
                                return row;
                            })
                            .toList();
                    assertThat(shown)
                            .describedAs("%s — %s", testCase.get("name"), testCase.get("why"))
                            .isEqualTo(testCase.get("expected"));
                }));
    }

    @SuppressWarnings("unchecked")
    private static EventOccurrences.Times times(Map<String, Object> fields) {
        return new EventOccurrences.Times(
                (String) fields.get("timeForm"),
                instant(fields.get("startsAt")),
                instant(fields.get("endsAt")),
                date(fields.get("startDate")),
                date(fields.get("endDate")),
                (String) fields.get("localStart"),
                (String) fields.get("localEnd"),
                (String) fields.get("timeZone"),
                (String) fields.get("rrule"),
                (Map<String, Object>) fields.getOrDefault("exceptions", Map.of()));
    }

    /** A window edge: local, or an instant in UTC for the TIMED cases. */
    private static LocalDateTime local(String raw) {
        return LocalDateTime.parse(raw.endsWith("Z") ? raw.substring(0, raw.length() - 1) : raw, LOCAL);
    }

    private static OffsetDateTime instant(Object raw) {
        return raw == null ? null : OffsetDateTime.parse((String) raw);
    }

    private static LocalDate date(Object raw) {
        return raw == null ? null : LocalDate.parse((String) raw);
    }

    private static String format(LocalDateTime value, boolean utc) {
        return LOCAL.format(value) + (utc ? "Z" : "");
    }
}
