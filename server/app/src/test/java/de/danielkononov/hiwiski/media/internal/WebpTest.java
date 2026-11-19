package de.danielkononov.hiwiski.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.io.ByteArrayOutputStream;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** The size of a WebP, from each of its three layouts. */
class WebpTest {

    @TempDir Path root;

    /** RIFF/WEBP around one chunk. */
    static byte[] webp(String chunk, byte[] data) {
        var out = new ByteArrayOutputStream();
        out.writeBytes("RIFF".getBytes());
        out.writeBytes(le32(4 + 8 + data.length));
        out.writeBytes("WEBP".getBytes());
        out.writeBytes(chunk.getBytes());
        out.writeBytes(le32(data.length));
        out.writeBytes(data);
        return out.toByteArray();
    }

    static byte[] lossy(int width, int height) {
        byte[] data = new byte[10];
        // Frame tag (3), start code (3), then width and height in 14 bits each.
        data[3] = (byte) 0x9d;
        data[4] = 0x01;
        data[5] = 0x2a;
        data[6] = (byte) width;
        data[7] = (byte) (width >> 8);
        data[8] = (byte) height;
        data[9] = (byte) (height >> 8);
        return webp("VP8 ", data);
    }

    static byte[] lossless(int width, int height) {
        int w = width - 1;
        int h = height - 1;
        long bits = (w & 0x3fffL) | ((h & 0x3fffL) << 14);
        byte[] data = new byte[10];
        data[0] = 0x2f;
        for (int i = 0; i < 4; i++) {
            data[1 + i] = (byte) (bits >> (8 * i));
        }
        return webp("VP8L", data);
    }

    static byte[] extended(int width, int height) {
        byte[] data = new byte[10];
        for (int i = 0; i < 3; i++) {
            data[4 + i] = (byte) ((width - 1) >> (8 * i));
            data[7 + i] = (byte) ((height - 1) >> (8 * i));
        }
        return webp("VP8X", data);
    }

    private static byte[] le32(int value) {
        return new byte[] {(byte) value, (byte) (value >> 8), (byte) (value >> 16), (byte) (value >> 24)};
    }

    @Test
    void eachLayoutSaysItsSize() {
        assertThat(Webp.size(lossy(1024, 768))).isEqualTo(new Webp.Size(1024, 768));
        assertThat(Webp.size(lossless(16383, 3))).isEqualTo(new Webp.Size(16383, 3));
        assertThat(Webp.size(extended(16_777_216, 1))).isEqualTo(new Webp.Size(16_777_216, 1));
    }

    @Test
    void anUnknownOrShortChunkSaysNoSize() {
        assertThat(Webp.size(webp("ALPH", new byte[10]))).isNull();
        assertThat(Webp.size(webp("VP8 ", new byte[10]))).isNull();
        assertThat(Webp.size(webp("VP8X", new byte[4]))).isNull();
    }

    @Test
    void theStoreKeepsTheSizeOfAWebpAndRefusesOneTooLarge() {
        var store = new MediaStore(root.toString());

        var stored = store.put(lossless(4000, 3000));
        assertThat(stored.width()).isEqualTo(4000);
        assertThat(stored.height()).isEqualTo(3000);
        assertThat(store.preview(stored.sha256())).isNull();

        assertThatThrownBy(() -> store.put(lossy(16383, 16383)))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.too_large"));
        assertThatThrownBy(() -> store.put(webp("JUNK", new byte[10])))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.not_an_image"));
    }
}
