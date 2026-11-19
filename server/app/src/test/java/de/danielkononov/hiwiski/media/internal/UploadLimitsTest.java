package de.danielkononov.hiwiski.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.util.unit.DataSize;

/** Uploads processed a few at a time. */
class UploadLimitsTest {

    @Test
    void anUploadPastTheParallelOnesIsToldTheServerIsBusy() throws Exception {
        var limits = new UploadLimits(null, DataSize.ofGigabytes(1), 1, Duration.ofMillis(200));
        var started = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        var first = CompletableFuture.supplyAsync(() -> limits.inTurn(() -> {
            started.countDown();
            try {
                release.await();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            return "first";
        }));
        started.await();

        assertThatThrownBy(() -> limits.inTurn(() -> "second"))
                .isInstanceOfSatisfying(HiwiskiException.class, e -> {
                    assertThat(e.code()).isEqualTo("media.busy");
                    assertThat(e.status()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
                    assertThat(e.params()).containsKey(HiwiskiException.RETRY_AFTER_SECONDS);
                });

        release.countDown();
        assertThat(first.get()).isEqualTo("first");
        // The turn is free again -- also after a failure inside it.
        assertThatThrownBy(() -> limits.inTurn(() -> {
                    throw new IllegalStateException("decoder");
                }))
                .isInstanceOf(IllegalStateException.class);
        assertThat(limits.inTurn(() -> "third")).isEqualTo("third");
    }

    @Test
    void parallelUploadsAreAtLeastOne() {
        assertThatThrownBy(() -> new UploadLimits(null, DataSize.ofGigabytes(1), 0, Duration.ofMillis(1)))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
