package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.recurrence.Recurrence;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The local times of an event, checked before they reach a feed. */
class EventFieldCheckTest {

    private static final Recurrence ANY_RULE = new Recurrence() {
        @Override
        public List<LocalDateTime> expand(
                String rrule, LocalDateTime start, String timeZone, LocalDateTime from, LocalDateTime to) {
            return List.of();
        }

        @Override
        public boolean accepts(String rrule) {
            return true;
        }
    };

    // An extended year broke the feed for everyone.
    @ParameterizedTest
    @ValueSource(strings = {
        "+10000-01-01", "-0001-01-01", "0000-01-01", "+10000-01-01T10:00", "10000-01-01", "2026-1-01",
        "2026-02-30", "2026-02-30T10:00", "2026-10-19 12:00"
    })
    void aKeyOrTimeOutsideFourDigitYearsIsRefused(String value) {
        assertThat(EventFieldCheck.acceptable(Map.of("exceptions", Map.of(value, Map.of("cancelled", true))), ANY_RULE))
                .isFalse();
        assertThat(EventFieldCheck.acceptable(
                        Map.of("exceptions", Map.of("2026-10-19T12:00", Map.of("start", value))), ANY_RULE))
                .isFalse();
        assertThat(EventFieldCheck.acceptable(Map.of("localStart", value), ANY_RULE)).isFalse();
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-10-19T12:00", "2026-10-19T12:00:30", "0001-01-01T00:00", "9999-12-31T23:59"})
    void whatTheDevicesWriteIsAccepted(String value) {
        assertThat(EventFieldCheck.acceptable(
                        Map.of("localStart", value, "exceptions", Map.of(value, Map.of("start", value))), ANY_RULE))
                .isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-03-14", "0001-01-01", "9999-12-31"})
    void aDayIsAcceptedAsAnExceptionButNotAsALocalStart(String value) {
        assertThat(EventFieldCheck.acceptable(Map.of("exceptions", Map.of(value, Map.of("start", value))), ANY_RULE))
                .isTrue();
        assertThat(EventFieldCheck.acceptable(Map.of("localStart", value), ANY_RULE)).isFalse();
    }
}
