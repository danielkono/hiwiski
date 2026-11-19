package de.danielkononov.hiwiski.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** When a refresh deletes nothing: a source that looks broken rather than changed. */
class SubscriptionOutageTest {

    @Test
    void anEmptyFileIsAnOutage() {
        assertThat(SubscriptionService.looksLikeAnOutage(2, 2, 0)).isTrue();
    }

    @Test
    void nineInTenGoneIsAnOutage() {
        assertThat(SubscriptionService.looksLikeAnOutage(100, 95, 5)).isTrue();
    }

    @Test
    void aFewGoneIsAChange() {
        assertThat(SubscriptionService.looksLikeAnOutage(100, 3, 97)).isFalse();
        assertThat(SubscriptionService.looksLikeAnOutage(2, 1, 1)).isFalse();
    }
}
