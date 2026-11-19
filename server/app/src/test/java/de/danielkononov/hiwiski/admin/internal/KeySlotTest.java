package de.danielkononov.hiwiski.admin.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.json.JsonMapper;

class KeySlotTest {

    private static final String IDENTITY =
            "AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ";

    @Test
    void opensWithItsPasswordOnly() {
        var slot = KeySlot.wrap(IDENTITY, "richtiges-passwort", 1);
        var read = KeySlot.fromBytes(slot.toBytes()).orElseThrow();

        assertThat(read.unwrap("richtiges-passwort")).contains(IDENTITY);
        assertThat(read.unwrap("falsches-passwort")).isEmpty();
        assertThat(read.counter()).isEqualTo(1);
    }

    /** A slot cut off by a power cut is not a slot -- not a key that opens with nothing. */
    @Test
    void aSlotNotWrittenWholeIsNone() {
        byte[] bytes = KeySlot.wrap(IDENTITY, "richtiges-passwort", 1).toBytes();
        bytes[40] ^= 1;

        assertThat(KeySlot.fromBytes(bytes)).isEmpty();
        assertThat(KeySlot.fromBytes(new byte[KeySlot.SIZE])).isEmpty();
    }

    /**
     * A change of password writes the slot not in use. The other one stays, so the old
     * password still opens until the new slot is whole; after, the newer one wins.
     */
    @Test
    void aNewPasswordGoesIntoTheSpareSlot(@TempDir Path directory) throws Exception {
        var json = JsonMapper.builder().build();
        var header = new ArchiveHeader(
                new ArchiveHeader.Info(Instant.now(), "1.0.0", "036", BackupReason.SCHEDULED, null, "age1test"),
                Optional.of(KeySlot.wrap(IDENTITY, "altes-passwort", 1)),
                Optional.empty());
        Path file = directory.resolve("a.hiwiski");
        Files.write(file, header.toBytes(json));

        ArchiveHeader.writeSpareSlot(file, header, KeySlot.wrap(IDENTITY, "neues-passwort", 2));
        var changed = ArchiveHeader.read(file, json).orElseThrow();

        assertThat(changed.slotA().orElseThrow().unwrap("altes-passwort")).contains(IDENTITY);
        assertThat(changed.current().orElseThrow().unwrap("neues-passwort")).contains(IDENTITY);
        assertThat(changed.info().recipient()).isEqualTo("age1test");

        // And the next change goes back into the first slot.
        ArchiveHeader.writeSpareSlot(file, changed, KeySlot.wrap(IDENTITY, "drittes-passwort", 3));
        var again = ArchiveHeader.read(file, json).orElseThrow();
        assertThat(again.current().orElseThrow().unwrap("drittes-passwort")).contains(IDENTITY);
        assertThat(again.slotB().orElseThrow().unwrap("neues-passwort")).contains(IDENTITY);
    }

    @Test
    void aFileThatIsNoArchiveHasNoHeader(@TempDir Path directory) throws Exception {
        Path file = directory.resolve("b.hiwiski");
        Files.writeString(file, "PK\u0003\u0004 an old zip archive");

        assertThat(ArchiveHeader.read(file, JsonMapper.builder().build())).isEmpty();
    }

    /**
     * The parameters stand in the file, and an uploaded file is anybody's. One that
     * names gigabytes of memory or hundreds of passes is no slot: read as one, it took
     * the server down before a password was checked.
     */
    @Test
    void aSlotAskingForTooMuchIsNone() {
        var slot = KeySlot.wrap(IDENTITY, "richtiges-passwort", 1);

        var greedy = new KeySlot(
                slot.counter(), 4 * 1024 * 1024, slot.iterations(), slot.parallelism(),
                slot.salt(), slot.nonce(), slot.wrapped());
        var endless = new KeySlot(
                slot.counter(), slot.memoryKiB(), 300, slot.parallelism(),
                slot.salt(), slot.nonce(), slot.wrapped());

        assertThat(KeySlot.fromBytes(greedy.toBytes())).isEmpty();
        assertThat(KeySlot.fromBytes(endless.toBytes())).isEmpty();
        assertThat(KeySlot.fromBytes(slot.toBytes())).isPresent();
    }
}
