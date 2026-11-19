package de.danielkononov.hiwiski;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.api.InvitationsApi;
import de.danielkononov.hiwiski.api.PlatformApi;
import de.danielkononov.hiwiski.support.PostgresContainer;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.web.context.WebApplicationContext;

/**
 * The whole application comes up the way a maintenance command starts it: without a web
 * server, against the real database.
 *
 * <p>{@code hiwiski reset-admin-password} used to fail before it did anything: two
 * controllers took the HTTP request in their constructors, and without a web server there
 * is none (platform.CurrentRequest). CommandModeTest only checked the web type; this
 * starts every bean.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = "hiwiski.command=context-check")
@ContextConfiguration(classes = PostgresContainer.class)
@ActiveProfiles("test")
@Tag("integration")
class CommandModeIT {

    @Autowired ApplicationContext context;

    @Test
    void theApplicationStartsWithoutAWebServer() {
        assertThat(context).isNotInstanceOf(WebApplicationContext.class);
        // The two that took the request in their constructors.
        assertThat(context.getBeanNamesForType(PlatformApi.class)).isNotEmpty();
        assertThat(context.getBeanNamesForType(InvitationsApi.class)).isNotEmpty();
    }
}
