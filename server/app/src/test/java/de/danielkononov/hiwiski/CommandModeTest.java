package de.danielkononov.hiwiski;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.scheduling.config.ScheduledTaskHolder;

/**
 * A maintenance command runs next to the live server: no second web server on its port,
 * no second set of scheduled jobs.
 */
class CommandModeTest {

    @Test
    void aCommandStartsWithoutAWebServer() {
        assertThat(HiwiskiApplication.application("--hiwiski.command=reset-admin-password").getWebApplicationType())
                .isEqualTo(WebApplicationType.NONE);
        assertThat(HiwiskiApplication.application().getWebApplicationType())
                .isNotEqualTo(WebApplicationType.NONE);
    }

    @Test
    void aCommandStartsNoScheduledJobs() {
        var runner = new ApplicationContextRunner().withUserConfiguration(Scheduling.class);

        runner.run(context -> assertThat(context).hasSingleBean(ScheduledTaskHolder.class));
        runner.withPropertyValues("hiwiski.command=reset-admin-password")
                .run(context -> assertThat(context).doesNotHaveBean(ScheduledTaskHolder.class));
    }
}
