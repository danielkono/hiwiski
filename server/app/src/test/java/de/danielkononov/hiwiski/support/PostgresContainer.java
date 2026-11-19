package de.danielkononov.hiwiski.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * One Postgres for the entire test run.
 *
 * <p>Tests never run against an in-memory database. Everything that defines this
 * application -- full-text search, JSONB, transactional DDL, the sequence counter with its
 * row lock -- is Postgres-specific. An H2 suite only proves that H2 works.
 *
 * <p>The container is not restarted per test class; Spring caches the application context
 * across classes anyway. Cleanup happens when the JVM exits.
 */
@TestConfiguration(proxyBeanMethods = false)
public class PostgresContainer {

    public static final String IMAGE = "postgres:18-alpine";

    @Bean
    @ServiceConnection
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer(IMAGE)
                .withDatabaseName("hiwiski")
                .withUsername("hiwiski")
                .withPassword("hiwiski");
    }
}
