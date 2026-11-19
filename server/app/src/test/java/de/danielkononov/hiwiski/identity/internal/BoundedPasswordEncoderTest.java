package de.danielkononov.hiwiski.identity.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

class BoundedPasswordEncoderTest {

    /** Parallel sign-ins do not all hash at once. */
    @Test
    void onlyTheGivenNumberOfHashesRunAtOnce() throws Exception {
        var running = new AtomicInteger();
        var peak = new AtomicInteger();
        var release = new CountDownLatch(1);
        PasswordEncoder slow = new PasswordEncoder() {
            @Override
            public String encode(CharSequence rawPassword) {
                return rawPassword.toString();
            }

            @Override
            public boolean matches(CharSequence rawPassword, String encodedPassword) {
                peak.accumulateAndGet(running.incrementAndGet(), Math::max);
                try {
                    release.await(5, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                running.decrementAndGet();
                return false;
            }
        };
        var bounded = new BoundedPasswordEncoder(slow, 2);

        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<Boolean>> checks = new ArrayList<>();
            for (int i = 0; i < 20; i++) {
                checks.add(executor.submit(() -> bounded.matches("guess", "hash")));
            }
            Thread.sleep(300);
            assertThat(running.get()).isEqualTo(2);
            release.countDown();
            for (var check : checks) {
                check.get(10, TimeUnit.SECONDS);
            }
        }
        assertThat(peak.get()).isEqualTo(2);
    }

    @Test
    void theNumberFollowsTheHeap() {
        long mib = 1024L * 1024;
        assertThat(BoundedPasswordEncoder.concurrentFor(128 * mib)).isEqualTo(1);
        assertThat(BoundedPasswordEncoder.concurrentFor(512 * mib)).isEqualTo(2);
        assertThat(BoundedPasswordEncoder.concurrentFor(16 * 1024 * mib)).isEqualTo(4);
    }
}
