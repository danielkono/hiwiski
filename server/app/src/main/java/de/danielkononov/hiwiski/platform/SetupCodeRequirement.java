package de.danielkononov.hiwiski.platform;

import org.jspecify.annotations.Nullable;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Whether the setup wizard asks for the setup code from the server's log.
 *
 * <p>Off by default. Until the wizard has run, whoever reaches the server first becomes
 * its administrator; on a family's home network that is the family, and making them
 * read a container log before they may start is a hurdle without a gain. On a server
 * reachable from the internet it is whoever is quickest, so its operator switches the
 * code on with {@code HIWISKI_SETUP_CODE_REQUIRED=true}.
 *
 * <p>A fixed {@code HIWISKI_SETUP_CODE} switches it on as well: whoever names a code
 * means it to be checked, and an automated install that set one before the code became
 * optional must not lose the check through an update.
 *
 * <p>Here rather than in the identity module, which checks the code, because the
 * handshake tells the app whether to ask for it.
 */
@Component
public class SetupCodeRequirement {

    private final boolean required;

    public SetupCodeRequirement(
            @Value("${hiwiski.setup-code-required:false}") boolean switchedOn,
            @Value("${hiwiski.setup-code:}") @Nullable String fixedCode) {
        this.required = switchedOn || (fixedCode != null && !fixedCode.isBlank());
    }

    /** Whether the wizard -- and a restore on a fresh server -- needs the code. */
    public boolean required() {
        return required;
    }
}
