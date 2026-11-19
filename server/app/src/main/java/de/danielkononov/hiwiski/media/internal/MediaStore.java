package de.danielkononov.hiwiski.media.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.security.MessageDigest;
import java.time.Instant;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Set;
import java.util.stream.Stream;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The bytes of the media store — in the file system under {@code HIWISKI_MEDIA_PATH},
 * named after their SHA-256.
 *
 * <p>The name is the content: the same image on two recipes is stored once, and a file
 * is never overwritten, only deleted when no row points to it any more.
 */
@Component
class MediaStore {

    /** "Two sizes: the original and a preview (longest edge 640)." */
    static final int PREVIEW_EDGE = 640;

    static final String PREVIEW_TYPE = "image/jpeg";

    private static final String PREVIEW_SUFFIX = ".preview.jpg";

    /** A file still being written. */
    static final String PART_SUFFIX = ".part";

    /**
     * What is accepted as an image — recognized by the first bytes, not by what the
     * client claims. A recipe photo comes from a camera or a browser.
     */
    private static final Set<String> TYPES = Set.of("image/jpeg", "image/png", "image/gif", "image/webp");

    private final Path root;

    MediaStore(@Value("${hiwiski.media-path}") String mediaPath) {
        this.root = Path.of(mediaPath);
    }

    record Stored(String sha256, String contentType, long byteSize, Integer width, Integer height) {}

    Stored put(byte[] upload) {
        var contentType = sniff(upload);
        if (contentType == null || !TYPES.contains(contentType)) {
            throw HiwiskiException.invalid("media.not_an_image");
        }
        // What is stored and served is the image without where and when it was taken:
        // the original goes to everyone who sees its carrier. The name is the content -- of the stripped bytes.
        var bytes = Metadata.strip(upload, contentType);
        var sha256 = sha256(bytes);
        try {
            // Read before anything is written: an image refused for its size leaves
            // nothing behind.
            var image = read(bytes, contentType);
            Files.createDirectories(root);
            var original = original(sha256);
            if (!Files.exists(original)) {
                // A temp file of its own: two uploads of the same photo at once -- a retry
                // while the first still runs -- shared `<sha>.part`, and one could move a
                // half-written file into place or fail on one moved away under it.
                // Renaming over a file that appeared meanwhile is fine: same name, same
                // bytes.
                var partial = Files.createTempFile(root, sha256, PART_SUFFIX);
                Files.write(partial, bytes);
                Files.move(partial, original, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
            } else {
                // The same bytes again: fresh as a new file, so the cleanup does not take
                // them while the row that points to them is still being written.
                Files.setLastModifiedTime(original, FileTime.from(Instant.now()));
            }
            if (image != null
                    && image.pixels() != null
                    && !Files.exists(root.resolve(sha256 + PREVIEW_SUFFIX))) {
                writePreview(image.pixels(), root.resolve(sha256 + PREVIEW_SUFFIX));
            }
            return new Stored(
                    sha256,
                    contentType,
                    bytes.length,
                    image == null ? null : image.width(),
                    image == null ? null : image.height());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    Path original(String sha256) {
        return root.resolve(sha256);
    }

    /** The preview — or {@code null} where the format did not allow one. */
    Path preview(String sha256) {
        var path = root.resolve(sha256 + PREVIEW_SUFFIX);
        return Files.exists(path) ? path : null;
    }

    void delete(String sha256) {
        try {
            Files.deleteIfExists(original(sha256));
            Files.deleteIfExists(root.resolve(sha256 + PREVIEW_SUFFIX));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * The hashes on disk last written before {@code cutoff} — for the cleanup.
     *
     * <p>Not the newer ones: an upload writes its file before its row commits, and a
     * file whose row is not visible yet would look orphaned.
     */
    Set<String> hashesOnDisk(Instant cutoff) {
        if (!Files.isDirectory(root)) return Set.of();
        try (Stream<Path> files = Files.list(root)) {
            return files.filter(path -> path.getFileName().toString().matches("[0-9a-f]{64}"))
                    .filter(path -> writtenBefore(path, cutoff))
                    .map(path -> path.getFileName().toString())
                    .collect(java.util.stream.Collectors.toSet());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * What a failed write leaves behind: temp files, and previews whose original is
     * gone. {@link #hashesOnDisk} sees neither, so they used to stay in the media
     * directory -- and in every backup -- for good.
     *
     * @param live the hashes that still have rows
     * @return how many files were removed
     */
    int deleteLeftovers(Instant cutoff, Set<String> live) {
        if (!Files.isDirectory(root)) return 0;
        try (Stream<Path> files = Files.list(root)) {
            int removed = 0;
            for (var path : files.toList()) {
                var name = path.getFileName().toString();
                boolean leftover = name.endsWith(PART_SUFFIX)
                        || (name.endsWith(PREVIEW_SUFFIX)
                                && !live.contains(name.substring(0, name.length() - PREVIEW_SUFFIX.length())));
                if (leftover && writtenBefore(path, cutoff) && Files.deleteIfExists(path)) {
                    removed++;
                }
            }
            return removed;
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static boolean writtenBefore(Path path, Instant cutoff) {
        try {
            return Files.getLastModifiedTime(path).toInstant().isBefore(cutoff);
        } catch (IOException gone) {
            return false;
        }
    }

    /**
     * More pixels than any camera a family uses takes. The header says how many before
     * a single one is decoded.
     */
    static final long MAX_PIXELS = 100_000_000L;

    /**
     * @param pixels decoded only as finely as the preview needs, or {@code null} where
     *     Java could not decode them
     * @param width the image's own width, not the decoded one
     */
    private record Decoded(BufferedImage pixels, int width, int height) {}

    /**
     * Reads the size from the header first and decodes no more than the preview needs.
     *
     * <p>{@code ImageIO.read} decodes the whole raster, however large the header claims
     * it is: a PNG of a few kilobytes declaring 50000×50000 pixels asks for ten
     * gigabytes, and the server goes down for the whole family.
     */
    private static Decoded read(byte[] bytes, String contentType) throws IOException {
        if ("image/webp".equals(contentType)) {
            // The size from the header -- the canvas, which bounds every frame -- and
            // the same cap as every other format, before anything is decoded.
            var size = Webp.size(bytes);
            if (size == null) {
                throw HiwiskiException.invalid("media.not_an_image");
            }
            checkPixels(size.width(), size.height());
            return new Decoded(webpPreview(bytes, size.width(), size.height()), size.width(), size.height());
        }
        try (ImageInputStream input = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            var readers = input == null ? null : ImageIO.getImageReaders(input);
            if (readers == null || !readers.hasNext()) {
                // A format Java cannot read: no preview and no dimensions, but the
                // image itself stays.
                return null;
            }
            ImageReader reader = readers.next();
            try {
                // A GIF's frames are counted first, so it may seek back to the first.
                reader.setInput(input, !"image/gif".equals(contentType), true);
                int width;
                int height;
                try {
                    width = reader.getWidth(0);
                    height = reader.getHeight(0);
                } catch (IOException | RuntimeException noHeader) {
                    // The right first bytes and nothing an image needs behind them.
                    throw HiwiskiException.invalid("media.not_an_image");
                }
                checkPixels(width, height);
                if ("image/gif".equals(contentType)) {
                    checkGif(bytes, reader);
                }
                // Every n-th pixel, so the decoded raster stays near twice the preview.
                int step = Math.max(1, Math.max(width, height) / (2 * PREVIEW_EDGE));
                ImageReadParam param = reader.getDefaultReadParam();
                param.setSourceSubsampling(step, step, 0, 0);
                // A phone stores a portrait photo lying on its side and says so in the
                // EXIF orientation. Browsers honor it for the original; the preview and
                // the stored size have to as well, or they show the photo sideways.
                int orientation = Exif.orientation(bytes);
                boolean turned = orientation >= 5 && orientation <= 8;
                try {
                    return new Decoded(
                            Exif.upright(reader.read(0, param), orientation),
                            turned ? height : width,
                            turned ? width : height);
                } catch (IOException | RuntimeException undecodable) {
                    // A CMYK JPEG from a print workflow, or a body Java's decoder trips
                    // over: the image is still the family's, it just gets no preview.
                    // It used to end the upload with a 500.
                    return new Decoded(null, turned ? height : width, turned ? width : height);
                }
            } finally {
                reader.dispose();
            }
        }
    }

    /**
     * The most pixels a WebP may have to get a preview. The WebP reader may decode the
     * whole raster before it subsamples; 16 megapixels are 64 MB on the heap per
     * upload in its turn.
     */
    static final long MAX_WEBP_PREVIEW_PIXELS = 16_000_000L;

    /**
     * The first frame of a WebP, decoded about as finely as the preview needs -- or
     * {@code null} where it cannot be read or is too large to decode here.
     *
     * <p>A WebP used to get no preview at all, so {@code /preview} served the original:
     * an animated avatar with a 10000×10000 canvas went to every member's app as it was,
     * hundreds of megabytes per frame decoded. With a
     * preview, avatars and thumbnails are a still JPEG of at most 640 pixels.
     */
    private static BufferedImage webpPreview(byte[] bytes, int width, int height) {
        if ((long) width * height > MAX_WEBP_PREVIEW_PIXELS) {
            return null;
        }
        try (ImageInputStream input = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            var readers = ImageIO.getImageReadersByMIMEType("image/webp");
            if (input == null || !readers.hasNext()) {
                return null;
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                int step = Math.max(1, Math.max(width, height) / (2 * PREVIEW_EDGE));
                ImageReadParam param = reader.getDefaultReadParam();
                param.setSourceSubsampling(step, step, 0, 0);
                return reader.read(0, param);
            } finally {
                reader.dispose();
            }
        } catch (IOException | RuntimeException undecodable) {
            return null;
        }
    }

    /**
     * A GIF's logical screen and every frame, not only the first frame.
     *
     * <p>ImageIO reports the first frame's size. The apps' decoder takes the logical
     * screen (bytes 6 to 9) as the canvas, so a 30000×30000 screen around a single 1×1
     * frame passed the cap and asked every phone that opened it for 3.6 GB.
     */
    private static void checkGif(byte[] bytes, ImageReader reader) {
        if (bytes.length < 10) {
            throw HiwiskiException.invalid("media.not_an_image");
        }
        int screenWidth = (bytes[6] & 0xff) | (bytes[7] & 0xff) << 8;
        int screenHeight = (bytes[8] & 0xff) | (bytes[9] & 0xff) << 8;
        if (screenWidth > 0 || screenHeight > 0) {
            // A screen of 0×0 is rare and means "as large as the frames" to decoders.
            checkPixels(Math.max(screenWidth, 1), Math.max(screenHeight, 1));
        }
        int frames;
        try {
            frames = reader.getNumImages(true);
        } catch (IOException | RuntimeException broken) {
            // Frames after the first that Java cannot read: the apps' decoder stops
            // there as well; the screen and the first frame are checked.
            return;
        }
        for (int frame = 1; frame < frames; frame++) {
            int width;
            int height;
            try {
                width = reader.getWidth(frame);
                height = reader.getHeight(frame);
            } catch (IOException | RuntimeException broken) {
                return;
            }
            checkPixels(width, height);
        }
    }

    private static void checkPixels(int width, int height) {
        if (width <= 0 || height <= 0 || (long) width * height > MAX_PIXELS) {
            throw HiwiskiException.invalid("media.too_large", "width", width, "height", height);
        }
    }

    private static void writePreview(BufferedImage image, Path target) throws IOException {
        var scale = Math.min(1.0, (double) PREVIEW_EDGE / Math.max(image.getWidth(), image.getHeight()));
        var width = Math.max(1, (int) Math.round(image.getWidth() * scale));
        var height = Math.max(1, (int) Math.round(image.getHeight() * scale));
        // JPEG has no transparency: on white, instead of a PNG turning black.
        var preview = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        var graphics = preview.createGraphics();
        try {
            graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
            graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
            graphics.setColor(java.awt.Color.WHITE);
            graphics.fillRect(0, 0, width, height);
            graphics.drawImage(image, 0, 0, width, height, null);
        } finally {
            graphics.dispose();
        }
        var partial = Files.createTempFile(target.getParent(), target.getFileName().toString(), PART_SUFFIX);
        ImageIO.write(preview, "jpg", partial.toFile());
        Files.move(partial, target, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
    }

    private static String sniff(byte[] b) {
        if (b.length >= 3 && (b[0] & 0xff) == 0xff && (b[1] & 0xff) == 0xd8 && (b[2] & 0xff) == 0xff) {
            return "image/jpeg";
        }
        if (b.length >= 8 && (b[0] & 0xff) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') {
            return "image/png";
        }
        if (b.length >= 6 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F') {
            return "image/gif";
        }
        if (b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
                && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') {
            return "image/webp";
        }
        return null;
    }

    private static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
