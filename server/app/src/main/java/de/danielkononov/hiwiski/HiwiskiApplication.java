package de.danielkononov.hiwiski;

import java.util.Arrays;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.modulith.Modulith;

/**
 * The entry point.
 *
 * <p>{@link Modulith} draws the module boundaries along the top-level packages below
 * this one. Which ones they are is in {@code docs/development/server.md}; that they are
 * respected is checked by {@code ModularityTest} on every build -- the boundaries are
 * verified in the build, not merely claimed.
 */
@Modulith(
        systemName = "hiwiski",
        sharedModules = {"platform"})
@SpringBootApplication
@ConfigurationPropertiesScan
public class HiwiskiApplication {

    /** The argument that starts a maintenance command instead of the server. */
    static final String COMMAND = "--hiwiski.command=";

    public static void main(String[] args) {
        application(args).run(args);
    }

    /**
     * The application for these arguments.
     *
     * <p>A maintenance command ({@code hiwiski reset-admin-password}) runs inside the
     * container where the server already listens: as a web application it failed on
     * "port already in use" before it got to do anything. It starts without a web
     * server, and without the scheduled jobs ({@link Scheduling}), so it does not run
     * backups or imports next to the live instance.
     */
    static SpringApplication application(String... args) {
        SpringApplication application = new SpringApplication(HiwiskiApplication.class);
        if (Arrays.stream(args).anyMatch(arg -> arg.startsWith(COMMAND))) {
            application.setWebApplicationType(WebApplicationType.NONE);
        }
        return application;
    }
}
