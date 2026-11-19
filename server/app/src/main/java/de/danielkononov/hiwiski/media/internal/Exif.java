package de.danielkononov.hiwiski.media.internal;

import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * The one EXIF value the media store needs: how a JPEG is meant to be turned.
 *
 * <p>Read by hand rather than with a library: it is one tag in the first segments of the
 * file, and Java's own JPEG reader does not apply it.
 */
final class Exif {

    private static final int ORIENTATION_TAG = 0x0112;

    private Exif() {}

    /**
     * The EXIF orientation of a JPEG, 1 to 8 -- 1 (as stored) when there is none or the
     * file is not a JPEG.
     */
    static int orientation(byte[] jpeg) {
        try {
            if (jpeg.length < 4 || (jpeg[0] & 0xff) != 0xff || (jpeg[1] & 0xff) != 0xd8) {
                return 1;
            }
            int at = 2;
            while (at + 4 <= jpeg.length && (jpeg[at] & 0xff) == 0xff) {
                int marker = jpeg[at + 1] & 0xff;
                int length = ((jpeg[at + 2] & 0xff) << 8) | (jpeg[at + 3] & 0xff);
                if (marker == 0xda || length < 2) {
                    // The image data starts: no EXIF before it.
                    return 1;
                }
                int body = at + 4;
                if (marker == 0xe1 && length >= 8 && body + 6 <= jpeg.length
                        && jpeg[body] == 'E' && jpeg[body + 1] == 'x' && jpeg[body + 2] == 'i'
                        && jpeg[body + 3] == 'f' && jpeg[body + 4] == 0 && jpeg[body + 5] == 0) {
                    return fromTiff(ByteBuffer.wrap(jpeg, body + 6, Math.min(length - 8, jpeg.length - body - 6))
                            .slice());
                }
                at += 2 + length;
            }
        } catch (RuntimeException unreadable) {
            // A broken EXIF block is not worth refusing the photo over.
        }
        return 1;
    }

    private static int fromTiff(ByteBuffer tiff) {
        tiff.order(tiff.get(0) == 'I' ? ByteOrder.LITTLE_ENDIAN : ByteOrder.BIG_ENDIAN);
        int ifd = tiff.getInt(4);
        int entries = tiff.getShort(ifd) & 0xffff;
        for (int i = 0; i < entries; i++) {
            int entry = ifd + 2 + i * 12;
            if ((tiff.getShort(entry) & 0xffff) == ORIENTATION_TAG) {
                int value = tiff.getShort(entry + 8) & 0xffff;
                return value >= 1 && value <= 8 ? value : 1;
            }
        }
        return 1;
    }

    /** The image turned the way its orientation says. */
    static BufferedImage upright(BufferedImage image, int orientation) {
        if (orientation <= 1 || orientation > 8) {
            return image;
        }
        double w = image.getWidth();
        double h = image.getHeight();
        AffineTransform turn = switch (orientation) {
            case 2 -> new AffineTransform(-1, 0, 0, 1, w, 0);
            case 3 -> new AffineTransform(-1, 0, 0, -1, w, h);
            case 4 -> new AffineTransform(1, 0, 0, -1, 0, h);
            case 5 -> new AffineTransform(0, 1, 1, 0, 0, 0);
            case 6 -> new AffineTransform(0, 1, -1, 0, h, 0);
            case 7 -> new AffineTransform(0, -1, -1, 0, h, w);
            default -> new AffineTransform(0, -1, 1, 0, 0, w);
        };
        boolean turned = orientation >= 5;
        var target = new BufferedImage(
                turned ? image.getHeight() : image.getWidth(),
                turned ? image.getWidth() : image.getHeight(),
                BufferedImage.TYPE_INT_RGB);
        var graphics = target.createGraphics();
        try {
            graphics.drawImage(image, turn, null);
        } finally {
            graphics.dispose();
        }
        return target;
    }
}
