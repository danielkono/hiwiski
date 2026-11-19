package de.danielkononov.hiwiski.calendar.internal;

import java.util.UUID;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

/**
 * The way into the package-private service without making it public.
 *
 * <p>The test feeds in a file without a server delivering it — otherwise it would need a
 * second container just for that, and a test with more setup than substance eventually
 * gets skipped.
 *
 * <p>As a `@TestConfiguration` and not a `@TestComponent`: if `@ContextConfiguration` lists
 * an ordinary component, Spring Boot considers the list complete and no longer adds the
 * application class — and then the web server does not start at all.
 */
@TestConfiguration(proxyBeanMethods = false)
public class SubscriptionTestAccess {

    @Bean
    Access subscriptionAccessForTests(SubscriptionService service) {
        return new Access(service);
    }

    /** The narrow view the test needs. */
    public record Access(SubscriptionService service) {

        public int apply(UUID subscriptionId, UUID calendarId, UUID owner, String ics) {
            return service.apply(subscriptionId, calendarId, owner, ics);
        }

        public int refresh(UUID subscriptionId) {
            return service.refresh(subscriptionId);
        }
    }
}
