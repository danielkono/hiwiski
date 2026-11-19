package de.danielkononov.hiwiski.media.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.Test;

/** Metadata out of the original, pixels untouched. */
class MetadataTest {

    static final String SECRET = "GPSLatitude=52.5200N";

    /** A JPEG with EXIF (orientation 6 and the secret), XMP with it, and a comment. */
    static byte[] jpegWithMetadata(int width, int height) throws IOException {
        var plain = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "jpg", plain);
        byte[] jpeg = plain.toByteArray();

        // EXIF: the orientation segment the store writes itself, with the secret after
        // the IFD where a GPS block would be.
        byte[] orientation = Metadata.orientationSegment(6);
        byte[] secret = SECRET.getBytes(StandardCharsets.US_ASCII);
        var exif = new ByteArrayOutputStream();
        int exifLength = orientation.length - 2 + secret.length;
        exif.write(0xff);
        exif.write(0xe1);
        exif.write(exifLength >> 8);
        exif.write(exifLength & 0xff);
        exif.write(orientation, 4, orientation.length - 4);
        exif.writeBytes(secret);

        var out = new ByteArrayOutputStream();
        out.write(jpeg, 0, 2);
        // ImageIO writes APP0 (JFIF) first: keep it first.
        int app0 = 2 + 2 + (((jpeg[4] & 0xff) << 8) | (jpeg[5] & 0xff));
        out.write(jpeg, 2, app0 - 2);
        out.writeBytes(exif.toByteArray());
        out.writeBytes(segment(0xe1, "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>" + SECRET + "</x:xmpmeta>"));
        out.writeBytes(segment(0xed, "Photoshop 3.0\0" + SECRET));
        out.writeBytes(segment(0xfe, SECRET));
        out.write(jpeg, app0, jpeg.length - app0);
        return out.toByteArray();
    }

    private static byte[] segment(int marker, String body) {
        byte[] bytes = body.getBytes(StandardCharsets.ISO_8859_1);
        var out = new ByteArrayOutputStream();
        out.write(0xff);
        out.write(marker);
        out.write((bytes.length + 2) >> 8);
        out.write((bytes.length + 2) & 0xff);
        out.writeBytes(bytes);
        return out.toByteArray();
    }

    private static boolean contains(byte[] haystack, String needle) {
        return new String(haystack, StandardCharsets.ISO_8859_1).contains(needle);
    }

    private static int indexOfScan(byte[] jpeg) {
        for (int i = 2; i + 1 < jpeg.length; i++) {
            if ((jpeg[i] & 0xff) == 0xff && (jpeg[i + 1] & 0xff) == 0xda) return i;
        }
        return -1;
    }

    @Test
    void aJpegLosesItsMetadataButKeepsItsPixelsAndOrientation() throws IOException {
        byte[] jpeg = jpegWithMetadata(64, 32);
        assertThat(contains(jpeg, SECRET)).isTrue();
        assertThat(Exif.orientation(jpeg)).isEqualTo(6);

        byte[] stripped = Metadata.strip(jpeg, "image/jpeg");

        assertThat(contains(stripped, SECRET)).isFalse();
        assertThat(Exif.orientation(stripped)).isEqualTo(6);
        // Not decoded again: the scan data is the same, byte for byte.
        assertThat(Arrays.copyOfRange(stripped, indexOfScan(stripped), stripped.length))
                .isEqualTo(Arrays.copyOfRange(jpeg, indexOfScan(jpeg), jpeg.length));
        var image = ImageIO.read(new ByteArrayInputStream(stripped));
        assertThat(image.getWidth()).isEqualTo(64);
        assertThat(image.getHeight()).isEqualTo(32);
        // JFIF stays first.
        assertThat(stripped[2] & 0xff).isEqualTo(0xff);
        assertThat(stripped[3] & 0xff).isEqualTo(0xe0);
    }

    @Test
    void aJpegWithoutMetadataStaysTheSameArray() throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(8, 8, BufferedImage.TYPE_INT_RGB), "jpg", out);
        byte[] jpeg = out.toByteArray();

        assertThat(Metadata.strip(jpeg, "image/jpeg")).isSameAs(jpeg);
    }

    // A Motion Photo carries its video, and the
    // video's GPS position, after the JPEG's end.
    @Test
    void whatComesAfterTheEndOfAJpegIsDropped() throws IOException {
        byte[] jpeg = jpegWithMetadata(64, 32);
        byte[] trailer = ("\0\0\0\u0018ftypmp42" + SECRET).getBytes(StandardCharsets.ISO_8859_1);
        byte[] motionPhoto = concat(jpeg, trailer);

        byte[] stripped = Metadata.strip(motionPhoto, "image/jpeg");

        assertThat(contains(stripped, SECRET)).isFalse();
        assertThat(stripped[stripped.length - 2] & 0xff).isEqualTo(0xff);
        assertThat(stripped[stripped.length - 1] & 0xff).isEqualTo(0xd9);
        assertThat(stripped).isEqualTo(Metadata.strip(jpeg, "image/jpeg"));
        // Also when there was nothing else to drop.
        byte[] plain = plainJpeg(8, 8);
        assertThat(Metadata.strip(concat(plain, trailer), "image/jpeg")).isEqualTo(plain);
    }

    /**
     * An Ultra HDR photo: XMP that says it has a gain map, a multi-picture index, EXIF
     * behind the index, the gain map as a second JPEG, then a video.
     */
    @Test
    void aMultiPictureJpegLosesItsMetadataAndStaysValid() throws IOException {
        byte[] head = plainJpeg(64, 32);
        int app0 = 2 + 2 + (((head[4] & 0xff) << 8) | (head[5] & 0xff));
        byte[] xmp = segment(0xe1, "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta hdrgm:Version=\"1.0\">"
                + SECRET + "</x:xmpmeta>");
        byte[] exif = segment(0xe1, "Exif\0\0MM\0*" + SECRET);
        byte[] gainMap = plainJpeg(16, 8);
        int mpfAt = app0 + xmp.length;
        int mpfLength = 2 + 2 + 4 + 8 + 30 + 32;
        int primaryLength = mpfAt + mpfLength + exif.length + head.length - app0;
        byte[] mpf = multiPictureIndex(primaryLength, gainMap.length, primaryLength - (mpfAt + 8));
        assertThat(mpf).hasSize(mpfLength);
        byte[] photo = concat(
                Arrays.copyOfRange(head, 0, app0), xmp, mpf, exif,
                Arrays.copyOfRange(head, app0, head.length), gainMap,
                ("ftypmp42" + SECRET).getBytes(StandardCharsets.ISO_8859_1));

        byte[] stripped = Metadata.strip(photo, "image/jpeg");

        assertThat(contains(stripped, SECRET)).isFalse();
        assertThat(contains(stripped, "hdrgm:Version=\"1.0\"")).isTrue();
        assertThat(contains(stripped, "Item:Length=\"" + gainMap.length + "\"")).isTrue();
        // The index still points at the gain map, and the file ends with it.
        int tiff = indexOf(stripped, "MPF\0") + 4;
        int offset = ((stripped[tiff + 38 + 24] & 0xff) << 24) | ((stripped[tiff + 38 + 25] & 0xff) << 16)
                | ((stripped[tiff + 38 + 26] & 0xff) << 8) | (stripped[tiff + 38 + 27] & 0xff);
        assertThat(Arrays.copyOfRange(stripped, tiff + offset, stripped.length)).isEqualTo(gainMap);
        var image = ImageIO.read(new ByteArrayInputStream(stripped));
        assertThat(image.getWidth()).isEqualTo(64);
    }

    /** A big-endian MPF index of two pictures: the primary, and one at {@code offset}. */
    private static byte[] multiPictureIndex(int primaryLength, int secondLength, int offset) {
        var tiff = java.nio.ByteBuffer.allocate(8 + 30 + 32);
        tiff.put(new byte[] {'M', 'M', 0, 0x2a}).putInt(8);
        tiff.putShort((short) 2);
        // MP format version, "0100".
        tiff.putShort((short) 0xb000).putShort((short) 7).putInt(4).put(new byte[] {'0', '1', '0', '0'});
        // The MP entries, 16 bytes per picture, right after the IFD.
        tiff.putShort((short) 0xb002).putShort((short) 7).putInt(32).putInt(8 + 30);
        tiff.putInt(0);
        tiff.putInt(0x20030000).putInt(primaryLength).putInt(0).putInt(0);
        tiff.putInt(0).putInt(secondLength).putInt(offset).putInt(0);
        return segment(0xe2, "MPF\0" + new String(tiff.array(), StandardCharsets.ISO_8859_1));
    }

    private static byte[] plainJpeg(int width, int height) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "jpg", out);
        return out.toByteArray();
    }

    private static byte[] concat(byte[]... parts) {
        var out = new ByteArrayOutputStream();
        for (byte[] part : parts) {
            out.writeBytes(part);
        }
        return out.toByteArray();
    }

    private static int indexOf(byte[] haystack, String needle) {
        return new String(haystack, StandardCharsets.ISO_8859_1).indexOf(needle);
    }

    @Test
    void aBrokenJpegIsKeptAsItCame() {
        byte[] broken = {(byte) 0xff, (byte) 0xd8, (byte) 0xff, (byte) 0xe1, 0x7f, 0x7f, 1, 2};

        assertThat(Metadata.strip(broken, "image/jpeg")).isSameAs(broken);
    }

    @Test
    void aPngLosesItsTextChunks() throws IOException {
        var plain = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(20, 10, BufferedImage.TYPE_INT_RGB), "png", plain);
        byte[] png = plain.toByteArray();
        // After the signature (8) and IHDR (8 + 13 + 4).
        int afterHeader = 8 + 25;
        var out = new ByteArrayOutputStream();
        out.write(png, 0, afterHeader);
        out.writeBytes(chunk("tEXt", "Comment\0" + SECRET));
        out.writeBytes(chunk("eXIf", "MM\0*" + SECRET));
        out.write(png, afterHeader, png.length - afterHeader);
        byte[] withText = out.toByteArray();

        byte[] stripped = Metadata.strip(withText, "image/png");

        assertThat(contains(withText, SECRET)).isTrue();
        assertThat(contains(stripped, SECRET)).isFalse();
        assertThat(stripped).isEqualTo(png);
    }

    private static byte[] chunk(String type, String data) {
        byte[] bytes = data.getBytes(StandardCharsets.ISO_8859_1);
        var out = new ByteArrayOutputStream();
        out.writeBytes(java.nio.ByteBuffer.allocate(4).putInt(bytes.length).array());
        out.writeBytes(type.getBytes(StandardCharsets.US_ASCII));
        out.writeBytes(bytes);
        var crc = new java.util.zip.CRC32();
        crc.update(type.getBytes(StandardCharsets.US_ASCII));
        crc.update(bytes);
        out.writeBytes(java.nio.ByteBuffer.allocate(4).putInt((int) crc.getValue()).array());
        return out.toByteArray();
    }

    @Test
    void aWebpLosesItsExifAndXmpChunksAndTheirFlags() {
        byte[] header = new byte[10];
        header[0] = 0x08 | 0x04;
        byte[] image = WebpTest.lossless(30, 20);
        byte[] lossless = Arrays.copyOfRange(image, 12, image.length);
        byte[] secret = SECRET.getBytes(StandardCharsets.US_ASCII);

        var body = new ByteArrayOutputStream();
        body.writeBytes(riffChunk("VP8X", header));
        body.writeBytes(lossless);
        body.writeBytes(riffChunk("EXIF", secret));
        body.writeBytes(riffChunk("XMP ", secret));
        byte[] webp = riff(body.toByteArray());

        byte[] stripped = Metadata.strip(webp, "image/webp");

        assertThat(contains(stripped, SECRET)).isFalse();
        var expectedHeader = riffChunk("VP8X", new byte[10]);
        var expected = new ByteArrayOutputStream();
        expected.writeBytes(expectedHeader);
        expected.writeBytes(lossless);
        assertThat(stripped).isEqualTo(riff(expected.toByteArray()));
    }

    private static byte[] riffChunk(String type, byte[] data) {
        var out = new ByteArrayOutputStream();
        out.writeBytes(type.getBytes(StandardCharsets.US_ASCII));
        out.writeBytes(le32(data.length));
        out.writeBytes(data);
        if (data.length % 2 == 1) out.write(0);
        return out.toByteArray();
    }

    private static byte[] riff(byte[] chunks) {
        var out = new ByteArrayOutputStream();
        out.writeBytes("RIFF".getBytes(StandardCharsets.US_ASCII));
        out.writeBytes(le32(4 + chunks.length));
        out.writeBytes("WEBP".getBytes(StandardCharsets.US_ASCII));
        out.writeBytes(chunks);
        return out.toByteArray();
    }

    private static byte[] le32(int value) {
        return new byte[] {(byte) value, (byte) (value >> 8), (byte) (value >> 16), (byte) (value >> 24)};
    }

    /** What follows the image's end is not the image: a second file went out with it. */
    @Test
    void aPngLosesWhatFollowsItsEnd() throws IOException {
        var plain = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(20, 10, BufferedImage.TYPE_INT_RGB), "png", plain);
        byte[] png = plain.toByteArray();
        var appended = new ByteArrayOutputStream();
        appended.write(png);
        appended.write("<script>appended</script>".getBytes(java.nio.charset.StandardCharsets.US_ASCII));

        byte[] stripped = Metadata.strip(appended.toByteArray(), "image/png");

        assertThat(stripped).isEqualTo(png);
    }
}
