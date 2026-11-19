package de.danielkononov.hiwiski.identity.internal;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ApplicationContext;
import org.springframework.stereotype.Component;

/**
 * {@code docker compose exec app hiwiski reset-admin-password}.
 *
 * <p>The only way that works without a signed-in account. Every other
 * password is reset by the administrator through the app — but the administrator
 * has nobody above them, and there is no email. Without this way, someone eventually
 * locks themselves out, and with self-hosting there is no support channel.
 *
 * <p>English, because these lines are read by the person who runs the server.
 */
@Component
@ConditionalOnProperty(name = "hiwiski.command", havingValue = "reset-admin-password")
class ResetAdminPasswordCommand implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(ResetAdminPasswordCommand.class);

    private final MemberService members;
    private final Secrets secrets;
    private final ApplicationContext context;

    ResetAdminPasswordCommand(MemberService members, Secrets secrets, ApplicationContext context) {
        this.members = members;
        this.secrets = secrets;
        this.context = context;
    }

    @Override
    public void run(ApplicationArguments args) {
        var admin = members.administrator().orElse(null);
        if (admin == null) {
            log.error("No administrator account exists yet — run the setup wizard first.");
            System.exit(SpringApplication.exit(context, () -> 1));
            return;
        }

        String temporary = secrets.newTemporaryPassword();
        // must_change_password: on the next login the administrator picks their own. A
        // temporary password that stays around is a password in the terminal history.
        members.setPassword(admin.id(), temporary, true);

        // Deliberately via stdout and not the logger: these lines must not end up in the
        // log buffer that the app exports later.
        System.out.println();
        System.out.println("  Temporary password for '" + admin.username() + "': " + temporary);
        System.out.println("  Sign in with it once; hiwiski will ask for a new password immediately.");
        System.out.println();

        System.exit(SpringApplication.exit(context, () -> 0));
    }
}
