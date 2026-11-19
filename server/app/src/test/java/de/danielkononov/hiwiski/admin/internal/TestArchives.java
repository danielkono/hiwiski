package de.danielkononov.hiwiski.admin.internal;

import com.exceptionfactory.jagged.framework.stream.StandardDecryptingChannelFactory;
import com.exceptionfactory.jagged.framework.stream.StandardEncryptingChannelFactory;
import com.exceptionfactory.jagged.x25519.X25519RecipientStanzaReaderFactory;
import com.exceptionfactory.jagged.x25519.X25519RecipientStanzaWriterFactory;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.channels.Channels;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import tools.jackson.databind.json.JsonMapper;

/**
 * Takes an archive apart and puts it together again -- for the archives a server would
 * never write: one from an older schema, one with an entry that climbs out of its
 * directory.
 */
public final class TestArchives {

    private static final JsonMapper JSON = JsonMapper.builder().build();

    private TestArchives() {}

    /** The entries of {@code file}, in order, opened with {@code password}. */
    public static Map<String, byte[]> open(Path file, String password) throws Exception {
        var header = ArchiveHeader.read(file, JSON).orElseThrow();
        String identity = ArchiveReader.unlock(header, password);
        Map<String, byte[]> entries = new LinkedHashMap<>();
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.READ)) {
            channel.position(ArchiveHeader.SIZE);
            var decrypted = new StandardDecryptingChannelFactory()
                    .newDecryptingChannel(
                            channel, List.of(X25519RecipientStanzaReaderFactory.newRecipientStanzaReader(identity)));
            try (InputStream in = Channels.newInputStream(decrypted);
                    ZipInputStream zip = new ZipInputStream(in)) {
                for (ZipEntry entry = zip.getNextEntry(); entry != null; entry = zip.getNextEntry()) {
                    entries.put(entry.getName(), zip.readAllBytes());
                }
            }
        }
        return entries;
    }

    /** Writes {@code entries} as an archive with the header of {@code like}, to its recipient. */
    public static void write(Path like, Path target, Map<String, byte[]> entries) throws Exception {
        var header = ArchiveHeader.read(like, JSON).orElseThrow();
        byte[] head = new byte[ArchiveHeader.SIZE];
        try (InputStream in = Files.newInputStream(like)) {
            in.readNBytes(head, 0, head.length);
        }
        var zipped = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(zipped)) {
            for (var entry : entries.entrySet()) {
                zip.putNextEntry(new ZipEntry(entry.getKey()));
                zip.write(entry.getValue());
                zip.closeEntry();
            }
        }
        try (OutputStream out = Files.newOutputStream(target)) {
            out.write(head);
            try (var encrypted = new StandardEncryptingChannelFactory()
                            .newEncryptingChannel(
                                    Channels.newChannel(out),
                                    List.of(X25519RecipientStanzaWriterFactory.newRecipientStanzaWriter(
                                            header.info().recipient())));
                    OutputStream payload = Channels.newOutputStream(encrypted)) {
                payload.write(zipped.toByteArray());
            }
        }
    }

    /** The manifest of {@code entries} with {@code changes} applied. */
    @SuppressWarnings("unchecked")
    public static byte[] manifestWith(Map<String, byte[]> entries, Map<String, Object> changes) {
        Map<String, Object> manifest = new LinkedHashMap<>(JSON.readValue(entries.get(BackupWriter.MANIFEST), Map.class));
        manifest.putAll(changes);
        return JSON.writeValueAsBytes(manifest);
    }

    public static byte[] concat(byte[] first, byte[] second) {
        byte[] both = java.util.Arrays.copyOf(first, first.length + second.length);
        System.arraycopy(second, 0, both, first.length, second.length);
        return both;
    }

    /** Runs the backup before an update as the server does at start. */
    public static void backUpBeforeUpdate(
            org.jooq.DSLContext db, Path backupPath, Path mediaPath, String version) {
        BackupBeforeUpdate.backUpIfUpdated(db, JSON, backupPath, mediaPath, version);
    }
}
