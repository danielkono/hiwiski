package de.danielkononov.hiwiski.support;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.ContextConfiguration;

/** Boots the whole application against a real Postgres in a container. */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ContextConfiguration(
        classes = {
            PostgresContainer.class,
            TestHttpClient.class,
            de.danielkononov.hiwiski.calendar.internal.SubscriptionTestAccess.class,
            de.danielkononov.hiwiski.calendar.internal.IcsImporterTestAccess.class
        },
        initializers = TestDirectories.class)
@ExtendWith(DatabaseCleaner.class)
@ActiveProfiles("test")
@Tag("integration")
public @interface IntegrationTest {}
