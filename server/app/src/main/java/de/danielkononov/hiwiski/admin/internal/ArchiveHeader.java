package de.danielkononov.hiwiski.admin.internal;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.jspecify.annotations.Nullable;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/**
 * The part of an archive in front of the age payload -- the only part that is ours.
 *
 * <pre>
 *    0  "HIWISKI-BACKUP\n" and the format version (one byte)
 *   16  the public part: its length (two bytes) and JSON, up to offset 512
 *  512  key slot A ({@link KeySlot#SIZE} bytes)
 *  768  key slot B
 * 1024  the age file: a zip of data, images and manifest
 * </pre>
 *
 * <p><strong>Fixed size</strong>, so a change of password rewrites a slot in place
 * instead of copying gigabytes of photos. It writes the slot not in use and leaves the
 * other alone; whoever reads takes the valid slot with the higher counter. A power cut
 * mid-write leaves the old password working, never neither.
 *
 * <p>The public part is what the list shows without the password. Not secret, and not
 * trusted either: on restore the manifest <em>inside</em> the encrypted payload decides.
 */
record ArchiveHeader(Info info, Optional<KeySlot> slotA, Optional<KeySlot> slotB) {

    static final int SIZE = 1024;

    private static final byte[] MAGIC = "HIWISKI-BACKUP\n".getBytes(StandardCharsets.US_ASCII);
    private static final byte FORMAT = 1;
    private static final int INFO_OFFSET = 16;
    private static final int INFO_MAX = 512 - INFO_OFFSET - 2;
    private static final int SLOT_A = 512;
    private static final int SLOT_B = SLOT_A + KeySlot.SIZE;

    /**
     * What the list shows.
     *
     * @param recipient the age recipient the archive is encrypted to -- by it the list
     *     tells archives of the current key from those made before a new password
     * @param updateTo for a backup before an update, the version updated to
     */
    record Info(
            Instant createdAt,
            String serverVersion,
            String schemaVersion,
            BackupReason reason,
            @Nullable String updateTo,
            String recipient) {}

    /** The slot a reader uses: the valid one with the higher counter. */
    Optional<KeySlot> current() {
        if (slotA.isEmpty()) {
            return slotB;
        }
        if (slotB.isEmpty()) {
            return slotA;
        }
        return slotA.get().counter() >= slotB.get().counter() ? slotA : slotB;
    }

    byte[] toBytes(ObjectMapper json) {
        Map<String, Object> fields = new LinkedHashMap<>();
        fields.put("createdAt", info.createdAt().toString());
        fields.put("serverVersion", info.serverVersion());
        fields.put("schemaVersion", info.schemaVersion());
        fields.put("reason", info.reason().name());
        if (info.updateTo() != null) {
            fields.put("updateTo", info.updateTo());
        }
        fields.put("recipient", info.recipient());
        byte[] visible = json.writeValueAsBytes(fields);
        if (visible.length > INFO_MAX) {
            throw new IllegalStateException("backup header too long: " + visible.length);
        }
        ByteBuffer buffer = ByteBuffer.allocate(SIZE);
        buffer.put(MAGIC).put(FORMAT).putShort((short) visible.length).put(visible);
        slotA.ifPresent(slot -> buffer.put(SLOT_A, slot.toBytes()));
        slotB.ifPresent(slot -> buffer.put(SLOT_B, slot.toBytes()));
        return buffer.array();
    }

    /** The header of {@code file}, or empty if it is not an archive of ours. */
    static Optional<ArchiveHeader> read(Path file, ObjectMapper json) throws IOException {
        byte[] bytes = new byte[SIZE];
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.READ)) {
            ByteBuffer buffer = ByteBuffer.wrap(bytes);
            while (buffer.hasRemaining() && channel.read(buffer) >= 0) {
                // until full or at the end
            }
            if (buffer.hasRemaining()) {
                return Optional.empty();
            }
        }
        return parse(bytes, json);
    }

    static Optional<ArchiveHeader> parse(byte[] bytes, ObjectMapper json) {
        if (bytes.length < SIZE
                || !Arrays.equals(bytes, 0, MAGIC.length, MAGIC, 0, MAGIC.length)
                || bytes[MAGIC.length] != FORMAT) {
            return Optional.empty();
        }
        ByteBuffer buffer = ByteBuffer.wrap(bytes);
        int length = Short.toUnsignedInt(buffer.getShort(INFO_OFFSET));
        if (length > INFO_MAX) {
            return Optional.empty();
        }
        Map<String, Object> fields;
        try {
            fields = json.readValue(
                    new String(bytes, INFO_OFFSET + 2, length, StandardCharsets.UTF_8), new TypeReference<>() {});
        } catch (RuntimeException e) {
            return Optional.empty();
        }
        Info info;
        try {
            info = new Info(
                    Instant.parse(String.valueOf(fields.get("createdAt"))),
                    String.valueOf(fields.get("serverVersion")),
                    String.valueOf(fields.get("schemaVersion")),
                    BackupReason.valueOf(String.valueOf(fields.get("reason"))),
                    fields.get("updateTo") == null ? null : String.valueOf(fields.get("updateTo")),
                    String.valueOf(fields.get("recipient")));
        } catch (RuntimeException e) {
            return Optional.empty();
        }
        return Optional.of(new ArchiveHeader(
                info,
                KeySlot.fromBytes(Arrays.copyOfRange(bytes, SLOT_A, SLOT_A + KeySlot.SIZE)),
                KeySlot.fromBytes(Arrays.copyOfRange(bytes, SLOT_B, SLOT_B + KeySlot.SIZE))));
    }

    /**
     * Writes {@code slot} into the slot of {@code file} not in use, on disk before it
     * returns. The slot in use stays as it is -- until this one is whole, it is the one
     * a reader takes.
     */
    static void writeSpareSlot(Path file, ArchiveHeader header, KeySlot slot) throws IOException {
        boolean aInUse = header.current().isPresent() && header.current().equals(header.slotA());
        try (FileChannel channel = FileChannel.open(file, StandardOpenOption.WRITE)) {
            ByteBuffer buffer = ByteBuffer.wrap(slot.toBytes());
            long position = aInUse ? SLOT_B : SLOT_A;
            while (buffer.hasRemaining()) {
                position += channel.write(buffer, position);
            }
            channel.force(true);
        }
    }
}
