package de.danielkononov.hiwiski.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.CRC32;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class MediaStoreTest {

    @TempDir Path root;

    private static byte[] png(int width, int height) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "png", out);
        return out.toByteArray();
    }

    /** A real PNG whose header then claims another size — what a decompression bomb is. */
    private static byte[] claiming(byte[] png, int width, int height) {
        var bytes = png.clone();
        // Signature (8), length (4), "IHDR" (4), then width and height.
        ByteBuffer.wrap(bytes, 16, 8).putInt(width).putInt(height);
        var crc = new CRC32();
        crc.update(bytes, 12, 17);
        ByteBuffer.wrap(bytes, 29, 4).putInt((int) crc.getValue());
        return bytes;
    }

    @Test
    void anImageGetsItsSizeAndAPreview() throws IOException {
        var stored = new MediaStore(root.toString()).put(png(2000, 1000));

        assertThat(stored.width()).isEqualTo(2000);
        assertThat(stored.height()).isEqualTo(1000);
        var preview = ImageIO.read(root.resolve(stored.sha256() + ".preview.jpg").toFile());
        assertThat(preview.getWidth()).isEqualTo(MediaStore.PREVIEW_EDGE);
        assertThat(preview.getHeight()).isEqualTo(MediaStore.PREVIEW_EDGE / 2);
    }

    /**
     * A few kilobytes claiming 50000×50000 pixels: decoded whole, that is ten gigabytes
     * on the heap. It is refused from its header, and nothing is written.
     */
    @Test
    void anImageClaimingTooManyPixelsIsRefusedUnread() throws IOException {
        var bomb = claiming(png(8, 8), 50_000, 50_000);

        assertThatThrownBy(() -> new MediaStore(root.toString()).put(bomb))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.too_large"));
        try (var files = Files.list(root)) {
            assertThat(files).isEmpty();
        }
    }

    /**
     * A GIF by hand: a logical screen of the given size, then one 1×1 frame each for
     * the given frame sizes -- the descriptor claims the size, the data is one pixel.
     */
    private static byte[] gif(int screenWidth, int screenHeight, int... frameSizes) {
        var out = new ByteArrayOutputStream();
        out.writeBytes("GIF89a".getBytes(java.nio.charset.StandardCharsets.US_ASCII));
        writeShort(out, screenWidth);
        writeShort(out, screenHeight);
        out.writeBytes(new byte[] {0, 0, 0});
        for (int i = 0; i < frameSizes.length; i += 2) {
            out.write(0x2C);
            writeShort(out, 0);
            writeShort(out, 0);
            writeShort(out, frameSizes[i]);
            writeShort(out, frameSizes[i + 1]);
            // A local colour table of two entries, black and white.
            out.write(0x80);
            out.writeBytes(new byte[] {0, 0, 0, (byte) 0xff, (byte) 0xff, (byte) 0xff});
            // LZW, minimum code size 2: clear, index 0, end.
            out.writeBytes(new byte[] {2, 2, 0x44, 0x01, 0});
        }
        out.write(0x3B);
        return out.toByteArray();
    }

    private static void writeShort(ByteArrayOutputStream out, int value) {
        out.write(value & 0xff);
        out.write(value >> 8 & 0xff);
    }

    // ImageIO reports the first frame, the apps decode
    // the logical screen.
    @Test
    void aGifIsMeasuredByItsScreenAndEveryFrame() throws IOException {
        var store = new MediaStore(root.toString());

        assertThatThrownBy(() -> store.put(gif(30_000, 30_000, 1, 1)))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.too_large"));
        assertThatThrownBy(() -> store.put(gif(1, 1, 1, 1, 20_000, 20_000)))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.too_large"));
        try (var files = Files.list(root)) {
            assertThat(files).isEmpty();
        }

        var fine = store.put(gif(2, 2, 1, 1, 2, 2));
        assertThat(fine.width()).isEqualTo(1);
        assertThat(Files.exists(root.resolve(fine.sha256() + ".preview.jpg"))).isTrue();
    }

    /**
     * A WebP gets a still JPEG preview like every other format -- an animated one of
     * its first frame -- so avatars and thumbnails never load a WebP original.
     * Made with cwebp and img2webp, 64×32.
     */
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(strings = {"lossy.webp", "lossless.webp", "animated.webp"})
    void aWebpGetsAPreview(String name) throws IOException {
        byte[] webp;
        try (var in = MediaStoreTest.class.getResourceAsStream("/media/" + name)) {
            webp = in.readAllBytes();
        }

        var stored = new MediaStore(root.toString()).put(webp);

        assertThat(stored.contentType()).isEqualTo("image/webp");
        assertThat(stored.width()).isEqualTo(64);
        assertThat(stored.height()).isEqualTo(32);
        var preview = ImageIO.read(root.resolve(stored.sha256() + ".preview.jpg").toFile());
        assertThat(preview.getWidth()).isEqualTo(64);
        assertThat(preview.getHeight()).isEqualTo(32);
    }

    /** Readable header, broken pixels: kept, with its size, but without a preview. */
    @Test
    void anImageJavaCannotDecodeIsStoredWithoutPreview() throws IOException {
        var broken = png(100, 50);
        // Garbage in the compressed pixel data, after the IHDR chunk.
        for (int i = 41; i < broken.length - 12; i++) {
            broken[i] = (byte) 0xAB;
        }

        var stored = new MediaStore(root.toString()).put(broken);

        assertThat(stored.width()).isEqualTo(100);
        assertThat(stored.height()).isEqualTo(50);
        assertThat(Files.exists(root.resolve(stored.sha256()))).isTrue();
        assertThat(Files.exists(root.resolve(stored.sha256() + ".preview.jpg"))).isFalse();
    }

    /** The first bytes of a JPEG and nothing behind them is not an image. */
    @Test
    void magicBytesAloneAreNotAnImage() {
        var fake = new byte[] {(byte) 0xff, (byte) 0xd8, (byte) 0xff, 1, 2, 3, 4, 5};

        assertThatThrownBy(() -> new MediaStore(root.toString()).put(fake))
                .isInstanceOfSatisfying(
                        HiwiskiException.class, e -> assertThat(e.code()).isEqualTo("media.not_an_image"));
    }

    /**
     * An upload writes its file before its row commits. The cleanup only looks at files
     * older than its grace period -- and the same bytes uploaded again count as new.
     */
    @Test
    void theCleanupDoesNotSeeFreshFiles() throws IOException {
        var store = new MediaStore(root.toString());
        var bytes = png(10, 10);
        var stored = store.put(bytes);
        var original = root.resolve(stored.sha256());
        var dayAgo = java.time.Instant.now().minus(java.time.Duration.ofDays(2));

        assertThat(store.hashesOnDisk(java.time.Instant.now().minusSeconds(3600))).isEmpty();

        Files.setLastModifiedTime(original, java.nio.file.attribute.FileTime.from(dayAgo));
        assertThat(store.hashesOnDisk(java.time.Instant.now().minusSeconds(3600)))
                .containsExactly(stored.sha256());

        store.put(bytes);
        assertThat(store.hashesOnDisk(java.time.Instant.now().minusSeconds(3600))).isEmpty();
    }

    /** A retry while the first upload still runs, or two devices with the same photo. */
    @Test
    void theSameBytesUploadedAtOnceAllArrive() throws Exception {
        var store = new MediaStore(root.toString());
        var bytes = png(1200, 900);

        var uploads = java.util.stream.IntStream.range(0, 8)
                .mapToObj(i -> java.util.concurrent.CompletableFuture.supplyAsync(() -> store.put(bytes)))
                .toList();
        var hashes = uploads.stream().map(java.util.concurrent.CompletableFuture::join).map(MediaStore.Stored::sha256);

        assertThat(hashes).hasSize(8).containsOnly(uploads.getFirst().join().sha256());
        var original = root.resolve(uploads.getFirst().join().sha256());
        assertThat(Files.readAllBytes(original)).isEqualTo(bytes);
        try (var files = Files.list(root)) {
            assertThat(files.map(Path::toString)).noneMatch(name -> name.endsWith(MediaStore.PART_SUFFIX));
        }
    }

    @Test
    void oldTempFilesAndPreviewsWithoutAnOriginalAreLeftovers() throws IOException {
        var store = new MediaStore(root.toString());
        var kept = store.put(png(10, 10));
        var old = java.nio.file.attribute.FileTime.from(java.time.Instant.now().minus(java.time.Duration.ofDays(2)));
        var part = Files.writeString(root.resolve("abc.part"), "half");
        var orphanPreview = Files.writeString(root.resolve("f".repeat(64) + ".preview.jpg"), "x");
        var freshPart = Files.writeString(root.resolve("def.part"), "still writing");
        for (var path : java.util.List.of(part, orphanPreview, root.resolve(kept.sha256() + ".preview.jpg"))) {
            Files.setLastModifiedTime(path, old);
        }

        int removed = store.deleteLeftovers(java.time.Instant.now().minusSeconds(3600), java.util.Set.of(kept.sha256()));

        assertThat(removed).isEqualTo(2);
        assertThat(part).doesNotExist();
        assertThat(orphanPreview).doesNotExist();
        assertThat(freshPart).exists();
        assertThat(root.resolve(kept.sha256() + ".preview.jpg")).exists();
    }

    /** A JPEG with an EXIF APP1 segment saying how it is meant to be turned. */
    private static byte[] jpegWithOrientation(BufferedImage image, int orientation) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(image, "jpg", out);
        var jpeg = out.toByteArray();
        var tiff = ByteBuffer.allocate(26).order(java.nio.ByteOrder.LITTLE_ENDIAN);
        tiff.put((byte) 'I').put((byte) 'I').putShort((short) 42).putInt(8);
        tiff.putShort((short) 1).putShort((short) 0x0112).putShort((short) 3).putInt(1);
        tiff.putShort((short) orientation).putShort((short) 0).putInt(0);
        var exif = new ByteArrayOutputStream();
        exif.writeBytes(new byte[] {(byte) 0xff, (byte) 0xe1});
        int length = 2 + 6 + tiff.capacity();
        exif.write(length >> 8);
        exif.write(length & 0xff);
        exif.writeBytes(new byte[] {'E', 'x', 'i', 'f', 0, 0});
        exif.writeBytes(tiff.array());
        var result = new ByteArrayOutputStream();
        result.write(jpeg, 0, 2);
        result.writeBytes(exif.toByteArray());
        result.write(jpeg, 2, jpeg.length - 2);
        return result.toByteArray();
    }

    /**
     * A phone's portrait photo: stored landscape, EXIF orientation 6. Its size and
     * preview are upright, as the browser shows the original.
     */
    @Test
    void aPhotoIsStoredTheWayItIsMeantToBeTurned() throws IOException {
        var sideways = new BufferedImage(1600, 800, BufferedImage.TYPE_INT_RGB);
        var paint = sideways.createGraphics();
        paint.setColor(java.awt.Color.RED);
        // The top of the picture, lying on the left side of the stored pixels.
        paint.fillRect(0, 0, 400, 800);
        paint.dispose();

        var stored = new MediaStore(root.toString()).put(jpegWithOrientation(sideways, 6));

        assertThat(stored.width()).isEqualTo(800);
        assertThat(stored.height()).isEqualTo(1600);
        var preview = ImageIO.read(root.resolve(stored.sha256() + ".preview.jpg").toFile());
        assertThat(preview.getWidth()).isEqualTo(320);
        assertThat(preview.getHeight()).isEqualTo(640);
        var top = new java.awt.Color(preview.getRGB(160, 10));
        var bottom = new java.awt.Color(preview.getRGB(160, 630));
        assertThat(top.getRed()).isGreaterThan(200);
        assertThat(bottom.getRed()).isLessThan(60);
    }
}
