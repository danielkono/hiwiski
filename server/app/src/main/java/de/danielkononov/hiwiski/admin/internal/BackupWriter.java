package de.danielkononov.hiwiski.admin.internal;

import com.exceptionfactory.jagged.framework.stream.StandardEncryptingChannelFactory;
import com.exceptionfactory.jagged.x25519.X25519RecipientStanzaWriterFactory;
import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.channels.Channels;
import java.nio.channels.FileChannel;
import java.nio.channels.WritableByteChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.Record;
import org.jooq.Table;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.jspecify.annotations.Nullable;
import tools.jackson.databind.ObjectMapper;

/**
 * Writes an archive: the header, then an age file to the backup key's recipient holding
 * a zip of manifest, data and images.
 *
 * <p><strong>Logical instead of {@code pg_dump}.</strong> A dump would need the Postgres
 * tools in the application image; the base image is a JRE, and a package manager does
 * not belong in it. Instead every table is written as JSON lines and, on restore,
 * inserted again in dependency order. That is fast enough at family size, and portable
 * between Postgres versions. The price: what is not in the schema is not in it either.
 *
 * <p>No password is needed: the archive is encrypted to the public key. That is what
 * lets the server back up at two in the night without anyone typing.
 *
 * <p>A plain class, not a bean: the backup before an update runs before the application
 * context is up, on a {@link DSLContext} of its own.
 */
final class BackupWriter {

    private static final Logger log = LoggerFactory.getLogger(BackupWriter.class);

    static final String MANIFEST = "manifest.json";
    static final String DATA_PREFIX = "data/";
    static final String MEDIA_PREFIX = "media/";

    private final ObjectMapper json;
    private final Path mediaPath;

    BackupWriter(ObjectMapper json, Path mediaPath) {
        this.json = json;
        this.mediaPath = mediaPath;
    }

    /**
     * One backup of what {@code db} sees -- the caller gives it one snapshot for all
     * tables.
     *
     * @param serverVersion the version whose data this is
     * @param updateTo for a backup before an update, the version updated to
     */
    BackupArchive write(
            DSLContext db,
            BackupDirectory directory,
            BackupReason reason,
            String serverVersion,
            @Nullable String updateTo,
            String recipient,
            KeySlot slot)
            throws IOException {
        Files.createDirectories(directory.path());
        Instant now = Instant.now();
        String id = directory.newId(now);
        Path file = directory.fileOf(id);
        Path partial = directory.partOf(id);
        String schemaVersion = SchemaVersion.of(db, "public");
        var header = new ArchiveHeader(
                new ArchiveHeader.Info(now, serverVersion, schemaVersion, reason, updateTo, recipient),
                Optional.of(slot),
                Optional.empty());

        long rows = 0;
        try (FileChannel channel = FileChannel.open(partial, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            ByteBuffer head = ByteBuffer.wrap(header.toBytes(json));
            while (head.hasRemaining()) {
                channel.write(head);
            }
            try (WritableByteChannel encrypted = encryptingChannel(unclosed(channel), recipient);
                    OutputStream out = new BufferedOutputStream(Channels.newOutputStream(encrypted), 1 << 16);
                    ZipOutputStream zip = new ZipOutputStream(out)) {

                // First, so a preview reads it without decrypting the photos behind it.
                zip.putNextEntry(new ZipEntry(MANIFEST));
                zip.write(json.writeValueAsBytes(manifest(db, id, now, serverVersion, schemaVersion)));
                zip.closeEntry();

                for (Table<?> table : ArchiveTables.of(db, "public")) {
                    List<Field<?>> columns = ArchiveTables.columns(table);
                    zip.putNextEntry(new ZipEntry(DATA_PREFIX + table.getName() + ".jsonl"));
                    for (Record record : db.select(columns).from(table).fetch()) {
                        zip.write(json.writeValueAsString(ArchiveTables.toMap(record, columns))
                                .getBytes(StandardCharsets.UTF_8));
                        zip.write('\n');
                        rows++;
                    }
                    zip.closeEntry();
                }

                // Images belong in the archive: a backup that leaves the recipe photos
                // behind only half restores the recipes.
                if (Files.isDirectory(mediaPath)) {
                    try (var files = Files.walk(mediaPath)) {
                        for (Path media : files.filter(Files::isRegularFile).toList()) {
                            zip.putNextEntry(new ZipEntry(MEDIA_PREFIX + mediaPath.relativize(media)));
                            Files.copy(media, zip);
                            zip.closeEntry();
                        }
                    }
                }
            }
            channel.force(true);
        } catch (IOException | RuntimeException e) {
            Files.deleteIfExists(partial);
            throw e;
        }
        Files.move(partial, file, StandardCopyOption.ATOMIC_MOVE);
        log.info("backup {} ({}) written with {} rows", id, reason, rows);
        return new BackupArchive(id, file, header, Files.size(file));
    }

    /**
     * The file stays open past the age stream's end, to be forced to disk.
     *
     * <p>Closed once, it says so: the age stream writes its last chunk on close, and on
     * every close of a channel still open -- closed twice by the resources around it, it
     * appended a second last chunk, and no archive could be read to its end.
     */
    private static WritableByteChannel unclosed(FileChannel channel) {
        return new WritableByteChannel() {
            private boolean closed;

            @Override
            public int write(ByteBuffer source) throws IOException {
                return channel.write(source);
            }

            @Override
            public boolean isOpen() {
                return !closed && channel.isOpen();
            }

            @Override
            public void close() {
                // The caller closes the file.
                closed = true;
            }
        };
    }

    private static WritableByteChannel encryptingChannel(WritableByteChannel target, String recipient)
            throws IOException {
        try {
            return new StandardEncryptingChannelFactory()
                    .newEncryptingChannel(
                            target, List.of(X25519RecipientStanzaWriterFactory.newRecipientStanzaWriter(recipient)));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("the backup key's recipient is not usable", e);
        }
    }

    private static Map<String, Object> manifest(
            DSLContext db, String id, Instant createdAt, String serverVersion, String schemaVersion) {
        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("id", id);
        manifest.put("createdAt", createdAt.toString());
        manifest.put("serverVersion", serverVersion);
        manifest.put("schemaVersion", schemaVersion);
        // Plain SQL: the generated classes may describe a newer schema than this one.
        manifest.put("members", db.resultQuery("select count(*) from member").fetchOne(0, Integer.class));
        manifest.put(
                "familyName",
                db.resultQuery("select value from instance_setting where key = 'family.name'")
                        .fetchOne(0, String.class));
        manifest.put(
                "familyId",
                db.resultQuery("select value from instance_setting where key = 'family.id'")
                        .fetchOne(0, String.class));
        return manifest;
    }
}
