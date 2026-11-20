package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.platform.SetupCodeRequirement;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Duration;
import java.util.Locale;
import org.jspecify.annotations.Nullable;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.context.WebApplicationContext;

/**
 * The one-time code the setup wizard asks for.
 *
 * <p>Until the wizard has run, whoever reaches the server first becomes its
 * administrator. On a home network that is the family; on a server reachable from the
 * internet it is whoever is quickest -- a new certificate shows up in the public
 * Certificate Transparency logs within minutes, and scanners follow them. The code ties
 * the setup to whoever can read the server's log, which is whoever runs it.
 *
 * <p>Asked for only where the operator switched it on ({@link SetupCodeRequirement}):
 * a family on its home network sets up without it.
 *
 * <p>Printed to the log at every start while the instance is not set up; a new one each
 * time, unless {@code HIWISKI_SETUP_CODE} names one (for an automated deployment). It
 * is kept in memory only and is worthless once the wizard has run.
 */
@Component
class SetupCode {

    private static final Logger log = LoggerFactory.getLogger(SetupCode.class);

    /** Wrong codes free per client address, then one every so often. */
    static final int CLIENT_CAPACITY = 10;

    static final Duration CLIENT_REFILL = Duration.ofSeconds(30);

    private final String code;
    private final boolean required;
    private final InstanceSettings settings;
    private final ClientBudget clients =
            new ClientBudget("auth.too_many_attempts", CLIENT_CAPACITY, CLIENT_REFILL, Clock.systemUTC());

    SetupCode(
            Secrets secrets,
            InstanceSettings settings,
            SetupCodeRequirement requirement,
            @Value("${hiwiski.setup-code:}") String configured) {
        this.settings = settings;
        this.required = requirement.required();
        this.code = configured == null || configured.isBlank() ? secrets.newSetupCode() : configured.trim();
    }

    /** Once the server is up, so the line is near the end of the startup output. */
    @EventListener
    void announce(ApplicationReadyEvent event) {
        // Not for a maintenance command: it runs without a web server, and nobody runs
        // the wizard through it.
        if (!(event.getApplicationContext() instanceof WebApplicationContext)) {
            return;
        }
        if (settings.getBoolean(SettingKey.SETUP_COMPLETED, false)) {
            return;
        }
        // Stdout through the logger: this is what `docker compose logs app` shows.
        if (required) {
            log.warn("Setup code: {} -- the setup wizard asks for it. It changes with every start "
                    + "until the setup has run.", code);
            return;
        }
        // Starting with the same words as the code's line: the guides of older versions
        // say to look for it, and an app from before the code became optional still asks
        // for one.
        log.warn("Setup code: not required -- whoever opens the setup wizard first becomes the "
                + "administrator. An app that still asks for a code takes any text. On a server "
                + "reachable from the internet, set HIWISKI_SETUP_CODE_REQUIRED=true.");
    }

    /**
     * Refuses a missing or wrong code with {@code 403 setup.code_invalid}, and too many
     * wrong ones from one address with 429 -- where the code is asked for at all.
     */
    void require(@Nullable String given, String client) {
        if (!required) {
            return;
        }
        clients.spend(client);
        if (given == null || !MessageDigest.isEqual(normalize(given), normalize(code))) {
            throw HiwiskiException.forbidden("setup.code_invalid");
        }
        clients.refund(client);
    }

    @Scheduled(fixedDelay = 5 * 60 * 1000)
    void removeStaleClients() {
        clients.removeStale();
    }

    /** Upper case, without dashes and spaces: read off a log, it is typed by hand. */
    private static byte[] normalize(String value) {
        return value.replace("-", "").replace(" ", "").toUpperCase(Locale.ROOT).getBytes(StandardCharsets.UTF_8);
    }
}
