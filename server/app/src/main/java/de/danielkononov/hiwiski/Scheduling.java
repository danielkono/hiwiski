package de.danielkononov.hiwiski;

import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * The scheduled jobs -- backups, imports, retention -- for the server, not for a
 * maintenance command.
 *
 * <p>A command runs next to the live instance; with scheduling on, it would start the
 * same jobs a second time against the same database.
 */
@Configuration(proxyBeanMethods = false)
@EnableScheduling
@ConditionalOnExpression("'${hiwiski.command:}'.isEmpty()")
class Scheduling {}
