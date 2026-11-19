package de.danielkononov.hiwiski.recurrence;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.internal.RecurrenceTestAccess;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.ObjectMapper;

/**
 * Expansion against {@code golden/recurrence.json}.
 *
 * <p>The client tests the same file. "RRULE on both sides against the same golden file.
 * The most expensive grunt work in the project and the only way to make it reliable."
 *
 * <p>Not an integration test: expansion needs no database, and a test that boots a
 * container for it eventually gets skipped.
 */
class RecurrenceGoldenTest {

    private static final DateTimeFormatter LOCAL = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm");

    private static final Path GOLDEN = Path.of("../../golden/recurrence.json");

    @SuppressWarnings("unchecked")
    @TestFactory
    Stream<DynamicTest> everyCaseFromTheGoldenFile() throws Exception {
        var recurrence = RecurrenceTestAccess.create();
        Map<String, Object> document =
                new ObjectMapper().readValue(Files.readString(GOLDEN), Map.class);
        List<Map<String, Object>> cases = (List<Map<String, Object>>) document.get("cases");

        assertThat(cases).isNotEmpty();

        return cases.stream().map(testCase -> DynamicTest.dynamicTest(
                String.valueOf(testCase.get("name")),
                () -> {
                    List<LocalDateTime> actual = recurrence.expand(
                            (String) testCase.get("rrule"),
                            LocalDateTime.parse((String) testCase.get("start"), LOCAL),
                            (String) testCase.get("timeZone"),
                            LocalDateTime.parse((String) testCase.get("from"), LOCAL),
                            LocalDateTime.parse((String) testCase.get("to"), LOCAL));

                    assertThat(actual.stream().map(LOCAL::format).toList())
                            .describedAs("%s — %s", testCase.get("name"), testCase.get("why"))
                            .isEqualTo(testCase.get("expected"));
                }));
    }
}
