package de.danielkononov.hiwiski.media.internal;

/**
 * The size a WebP declares, read from its first chunk.
 *
 * <p>Java has no WebP reader, so a WebP used to be stored without its header ever being
 * read: a file of 30 bytes declaring 16384×16384 pixels was accepted, served as its own
 * preview, and every app that showed it decoded a gigabyte. The size sits in the first 30 bytes, in one of three layouts
 * (developers.google.com/speed/webp/docs/riff_container).
 */
final class Webp {

    /** RIFF header (12) plus chunk header (8): where the first chunk's data starts. */
    private static final int DATA = 20;

    private Webp() {}

    /** Width and height in pixels. */
    record Size(int width, int height) {}

    /**
     * The canvas of a WebP -- {@code null} when the first chunk is none of the three
     * WebP knows or too short to hold its size.
     */
    static Size size(byte[] b) {
        if (b.length < DATA + 10) {
            return null;
        }
        String chunk = new String(b, 12, 4, java.nio.charset.StandardCharsets.US_ASCII);
        return switch (chunk) {
            // Lossy: a key frame's start code, then 14 bits of width and of height.
            case "VP8 " -> (b[DATA + 3] & 0xff) == 0x9d && (b[DATA + 4] & 0xff) == 0x01 && (b[DATA + 5] & 0xff) == 0x2a
                    ? new Size(le16(b, DATA + 6) & 0x3fff, le16(b, DATA + 8) & 0x3fff)
                    : null;
            // Lossless: a signature byte, then width - 1 and height - 1 in 14 bits each.
            case "VP8L" -> (b[DATA] & 0xff) == 0x2f
                    ? new Size(
                            1 + (((b[DATA + 2] & 0x3f) << 8) | (b[DATA + 1] & 0xff)),
                            1 + (((b[DATA + 4] & 0x0f) << 10)
                                    | ((b[DATA + 3] & 0xff) << 2)
                                    | ((b[DATA + 2] & 0xc0) >> 6)))
                    : null;
            // Extended (animation, alpha, metadata): the canvas, minus one, in 24 bits.
            case "VP8X" -> new Size(1 + le24(b, DATA + 4), 1 + le24(b, DATA + 7));
            default -> null;
        };
    }

    private static int le16(byte[] b, int at) {
        return (b[at] & 0xff) | ((b[at + 1] & 0xff) << 8);
    }

    private static int le24(byte[] b, int at) {
        return le16(b, at) | ((b[at + 2] & 0xff) << 16);
    }
}
