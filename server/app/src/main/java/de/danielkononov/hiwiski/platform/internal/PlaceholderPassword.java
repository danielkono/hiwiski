package de.danielkononov.hiwiski.platform.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Says so when the database password is still the one from {@code .env.example}.
 *
 * <p>A warning, not a refusal: Postgres took the password when its volume was created,
 * and a server that stopped starting after an update would leave a family without its
 * data over something that takes a few commands to change.
 */
@Component
class PlaceholderPassword {

    private static final Logger log = LoggerFactory.getLogger(PlaceholderPassword.class);

    /** As {@code deploy/.env.example} ships it. */
    static final String PLACEHOLDER = "please-change";

    private final String password;

    PlaceholderPassword(@Value("${spring.datasource.password:}") String password) {
        this.password = password;
    }

    boolean placeholder() {
        return password != null && password.startsWith(PLACEHOLDER);
    }

    @EventListener
    void warn(ApplicationReadyEvent event) {
        if (placeholder()) {
            log.warn("HIWISKI_DB_PASSWORD is still the placeholder from .env.example. Change it in Postgres "
                    + "(alter role ... password ...) and in .env.");
        }
    }
}
