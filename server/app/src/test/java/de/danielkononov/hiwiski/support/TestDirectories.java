package de.danielkononov.hiwiski.support;

import java.nio.file.Path;
import java.util.Map;
import java.util.UUID;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.MapPropertySource;

/**
 * Media and backups in a directory of their own per Spring context.
 *
 * <p>A fixed {@code ${java.io.tmpdir}/hiwiski-test} survived every run and was shared by
 * every context: what an earlier or aborted run, or another test class, left there
 * changed what {@code BackupIT} archived and restored. Not {@code ${random.uuid}} in the
 * YAML: that is a new value at every lookup, and the media store and the backup would
 * each have read a directory of their own.
 */
public final class TestDirectories implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    @Override
    public void initialize(ConfigurableApplicationContext context) {
        Path root = Path.of(System.getProperty("java.io.tmpdir"), "hiwiski-test-" + UUID.randomUUID());
        context.getEnvironment()
                .getPropertySources()
                .addFirst(new MapPropertySource(
                        "testDirectories",
                        Map.of(
                                "hiwiski.media-path", root.resolve("media").toString(),
                                "hiwiski.backup-path", root.resolve("backup").toString())));
    }
}
