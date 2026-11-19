package de.danielkononov.hiwiski.recurrence;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.internal.RecurrenceTestAccess;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.ObjectMapper;

/**
 * Which rules may be stored, against {@code golden/recurrence-limits.json} -- the app
 * checks the same file.
 */
class RecurrenceLimitsGoldenTest {

    private static final Path GOLDEN = Path.of("../../golden/recurrence-limits.json");

    private final Recurrence recurrence = RecurrenceTestAccess.create();

    @SuppressWarnings("unchecked")
    @TestFactory
    Stream<DynamicTest> everyRuleFromTheGoldenFile() throws Exception {
        Map<String, Object> document = new ObjectMapper().readValue(Files.readString(GOLDEN), Map.class);
        var accepted = (List<String>) document.get("accepted");
        var refused = (List<String>) document.get("refused");

        assertThat(accepted).isNotEmpty();
        assertThat(refused).isNotEmpty();

        return Stream.concat(
                accepted.stream().map(rule -> DynamicTest.dynamicTest(
                        "accepts " + rule, () -> assertThat(recurrence.accepts(rule)).isTrue())),
                refused.stream().map(rule -> DynamicTest.dynamicTest(
                        "refuses " + rule, () -> assertThat(recurrence.accepts(rule)).isFalse())));
    }

    /**
     * The trial expansion catches what the list of parts does not name: the library
     * gives up on a rule that searches long without finding an occurrence -- here every
     * minute of a day that comes once in four years, which the devices could not expand
     * quickly either.
     */
    @Test
    void aRuleTheLibraryGivesUpOnIsRefusedQuickly() {
        long started = System.nanoTime();

        assertThat(recurrence.accepts("FREQ=MINUTELY;BYMONTH=2;BYMONTHDAY=29")).isFalse();
        assertThat(Duration.ofNanos(System.nanoTime() - started)).isLessThan(Duration.ofSeconds(5));
    }
}
