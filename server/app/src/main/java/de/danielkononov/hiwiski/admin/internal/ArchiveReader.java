package de.danielkononov.hiwiski.admin.internal;

import com.exceptionfactory.jagged.framework.stream.StandardDecryptingChannelFactory;
import com.exceptionfactory.jagged.x25519.X25519RecipientStanzaReaderFactory;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.channels.Channels;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/**
 * Opens an archive with the backup password: its header, its manifest, its contents.
 *
 * <p>Every failure here comes before anything is replaced -- a wrong password, a file
 * that is not an archive, one cut off or changed changes nothing.
 */
final class ArchiveReader {

    private final ObjectMapper json;

    ArchiveReader(ObjectMapper json) {
        this.json = json;
    }

    /** The archive's header, or {@code 400 admin.backup_invalid} if it is not one of ours. */
    ArchiveHeader header(Path file) {
        try {
            return ArchiveHeader.read(file, json).orElseThrow(() -> HiwiskiException.invalid("admin.backup_invalid"));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** The age identity in the header, or {@code 400 admin.backup_password_wrong}. */
    static String unlock(ArchiveHeader header, String password) {
        KeySlot slot = header.current().orElseThrow(() -> HiwiskiException.invalid("admin.backup_invalid"));
        return slot.unwrap(password == null ? "" : password)
                .orElseThrow(() -> HiwiskiException.invalid("admin.backup_password_wrong"));
    }

    /** The manifest -- the zip's first entry, read without decrypting what follows. */
    Manifest manifest(Path file, String identity) {
        try (InputStream payload = payload(file, identity);
                ZipInputStream zip = new ZipInputStream(payload)) {
            ZipEntry first = zip.getNextEntry();
            if (first == null || !BackupWriter.MANIFEST.equals(first.getName())) {
                throw HiwiskiException.invalid("admin.backup_invalid");
            }
            return parseManifest(zip.readAllBytes());
        } catch (IOException e) {
            throw HiwiskiException.invalid("admin.backup_invalid");
        }
    }

    /**
     * The archive, decrypted and unpacked into {@code target}.
     *
     * <p>Every entry has to stay inside it. An archive with an entry like
     * {@code media/../../app/x} would otherwise write wherever the process may write.
     *
     * <p>Read to its very end: age authenticates every chunk and marks the last one, so
     * an archive cut off or changed anywhere fails here -- before anything is replaced.
     */
    Manifest unpack(Path file, String identity, Path target) {
        Manifest manifest = null;
        try (InputStream payload = payload(file, identity);
                ZipInputStream zip = new ZipInputStream(payload)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                if (manifest == null) {
                    if (!BackupWriter.MANIFEST.equals(entry.getName())) {
                        throw HiwiskiException.invalid("admin.backup_invalid");
                    }
                    manifest = parseManifest(zip.readAllBytes());
                    continue;
                }
                Path destination = target.resolve(entry.getName()).normalize();
                if (!destination.startsWith(target) || destination.equals(target)) {
                    throw HiwiskiException.invalid("admin.backup_invalid", "entry", entry.getName());
                }
                if (entry.isDirectory()) {
                    continue;
                }
                Files.createDirectories(destination.getParent());
                Files.copy(zip, destination);
            }
            payload.transferTo(java.io.OutputStream.nullOutputStream());
        } catch (IOException e) {
            throw HiwiskiException.invalid("admin.backup_invalid");
        }
        if (manifest == null) {
            throw HiwiskiException.invalid("admin.backup_invalid");
        }
        return manifest;
    }

    private InputStream payload(Path file, String identity) throws IOException {
        FileChannel channel = FileChannel.open(file, StandardOpenOption.READ);
        try {
            channel.position(ArchiveHeader.SIZE);
            var decrypted = new StandardDecryptingChannelFactory()
                    .newDecryptingChannel(
                            channel, List.of(X25519RecipientStanzaReaderFactory.newRecipientStanzaReader(identity)));
            return new BufferedInputStream(Channels.newInputStream(decrypted), 1 << 16);
        } catch (GeneralSecurityException e) {
            channel.close();
            // The header's key opened, but the payload is not encrypted to it: a header
            // put in front of another archive.
            throw HiwiskiException.invalid("admin.backup_invalid");
        } catch (IOException | RuntimeException e) {
            channel.close();
            throw e;
        }
    }

    private Manifest parseManifest(byte[] bytes) {
        try {
            Map<String, Object> fields = json.readValue(bytes, new TypeReference<>() {});
            return new Manifest(
                    String.valueOf(fields.get("id")),
                    Instant.parse(String.valueOf(fields.get("createdAt"))),
                    String.valueOf(fields.get("serverVersion")),
                    String.valueOf(fields.get("schemaVersion")),
                    ((Number) fields.getOrDefault("members", 0)).intValue(),
                    fields.get("familyName") == null ? null : String.valueOf(fields.get("familyName")),
                    // Every archive names its family; one that does not is no archive of ours.
                    java.util.Objects.requireNonNull(fields.get("familyId")).toString());
        } catch (RuntimeException e) {
            throw HiwiskiException.invalid("admin.backup_invalid");
        }
    }
}
