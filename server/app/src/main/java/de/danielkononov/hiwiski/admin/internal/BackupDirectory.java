package de.danielkononov.hiwiski.admin.internal;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;
import de.danielkononov.hiwiski.platform.StartRefused;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import tools.jackson.databind.ObjectMapper;

/**
 * The directory the archives lie in -- on the host, not in a Docker volume.
 *
 * <p>A plain class, not a bean: the backup before an update uses it before the
 * application context is up.
 */
final class BackupDirectory {

    private static final Logger log = LoggerFactory.getLogger(BackupDirectory.class);

    static final String SUFFIX = ".hiwiski";

    /** An archive still being written. */
    private static final String PART = ".part";

    /**
     * What an id looks like: the second it was made in, and a counter for a second
     * one in the same second. Anything else names no archive -- and no path either.
     */
    private static final Pattern ID = Pattern.compile("\\d{8}-\\d{6}(-\\d{1,3})?");

    private static final DateTimeFormatter SECOND =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").withZone(ZoneOffset.UTC);

    private final Path path;
    private final ObjectMapper json;

    BackupDirectory(Path path, ObjectMapper json) {
        this.path = path;
        this.json = json;
    }

    Path path() {
        return path;
    }

    /**
     * Fails unless the server can write here. A share mounted read-only or owned by
     * someone else would otherwise fail at two in the night, unseen.
     */
    void requireWritable() {
        try {
            Files.createDirectories(path);
            Path probe = Files.createTempFile(path, ".write-check-", ".tmp");
            Files.delete(probe);
        } catch (IOException | SecurityException e) {
            throw new StartRefused(
                    "The backup directory " + path.toAbsolutePath() + " is not writable for the server (uid 1000).",
                    "Check HIWISKI_BACKUP_DIR in .env: the directory must exist on the host, be mounted writable "
                            + "and belong to uid 1000 -- the init service in the compose file sets that.",
                    e);
        }
    }

    /** A new id. Two backups in the same second -- the nightly one and a tap -- get one each. */
    String newId(Instant now) {
        String second = SECOND.format(now);
        String id = second;
        for (int n = 2; Files.exists(fileOf(id)) || Files.exists(partOf(id)); n++) {
            id = second + "-" + n;
        }
        return id;
    }

    Path fileOf(String id) {
        return path.resolve(id + SUFFIX);
    }

    /**
     * Written under a name of its own and only then given the real one: a backup cut
     * off midway would otherwise stay as half an archive.
     */
    Path partOf(String id) {
        return path.resolve(id + SUFFIX + PART);
    }

    Optional<BackupArchive> find(String id) {
        if (!ID.matcher(id).matches()) {
            return Optional.empty();
        }
        return read(fileOf(id));
    }

    /** Newest first. A file that is not an archive of ours is not listed. */
    List<BackupArchive> list() {
        if (!Files.isDirectory(path)) {
            return List.of();
        }
        try (var files = Files.list(path)) {
            return files.filter(file -> file.getFileName().toString().endsWith(SUFFIX))
                    .map(this::read)
                    .flatMap(Optional::stream)
                    .sorted(Comparator.comparing((BackupArchive archive) -> archive.header().info().createdAt())
                            .reversed())
                    .toList();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Keeps the newest {@code keep}, of every kind together. Called once a new one is
     * complete -- the oldest go only then.
     */
    void prune(int keep) {
        List<BackupArchive> all = list();
        for (int i = keep; i < all.size(); i++) {
            try {
                Files.deleteIfExists(all.get(i).file());
                log.info("backup {} removed, {} are kept", all.get(i).id(), keep);
            } catch (IOException e) {
                log.warn("could not remove old backup {}", all.get(i).id(), e);
            }
        }
    }

    private Optional<BackupArchive> read(Path file) {
        String name = file.getFileName().toString();
        String id = name.substring(0, name.length() - SUFFIX.length());
        if (!ID.matcher(id).matches()) {
            return Optional.empty();
        }
        try {
            return ArchiveHeader.read(file, json).map(header -> new BackupArchive(id, file, header, size(file)));
        } catch (IOException e) {
            log.warn("could not read the backup header of {}", file, e);
            return Optional.empty();
        }
    }

    private static long size(Path file) {
        try {
            return Files.size(file);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
