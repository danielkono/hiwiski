package de.danielkononov.hiwiski.media.internal;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Set;

/**
 * Takes what a photo says about where and when it was taken out of the original,
 * without decoding it again.
 *
 * <p>Only the preview used to be re-encoded, and so stripped; the original, served to
 * everyone who can see its carrier, kept its EXIF and XMP -- the GPS position of a
 * photo taken at home among them. The pixels stay exactly as they were: only whole
 * metadata blocks are dropped.
 *
 * <ul>
 *   <li>JPEG: APP1 (EXIF and XMP), APP13 (Photoshop/IPTC) and comments. The colour
 *       profile (APP2) and Adobe's colour transform (APP14) stay. The orientation stays
 *       too, as a minimal EXIF block of its own: without it a portrait photo shows on
 *       its side. The file ends at the image's EOI: a Motion Photo's video, with its
 *       GPS position, came along after it. A multi-picture file (MPF) loses the
 *       metadata of its primary picture also behind the index, whose offsets are moved
 *       along, and ends after its last picture; an Ultra HDR photo gets a gain-map XMP
 *       written here in place of the camera's. The secondary pictures are kept as they
 *       are.
 *   <li>PNG: {@code eXIf}, {@code tEXt}, {@code zTXt}, {@code iTXt} and {@code tIME}.
 *   <li>WebP: the {@code EXIF} and {@code XMP } chunks, and their flags.
 * </ul>
 *
 * <p>A file whose structure is not what its format says is kept as it came: it is the
 * family's image, and refusing it for its metadata would be worse than keeping them.
 * GIF is kept as it is; a camera does not write one.
 */
final class Metadata {

    private static final int SOI = 0xd8;
    private static final int SOS = 0xda;
    private static final int EOI = 0xd9;
    private static final int APP0 = 0xe0;
    private static final int APP1 = 0xe1;
    private static final int APP2 = 0xe2;
    private static final int APP13 = 0xed;
    private static final int COM = 0xfe;

    private static final Set<String> PNG_METADATA = Set.of("eXIf", "tEXt", "zTXt", "iTXt", "tIME");

    private static final Set<String> WEBP_METADATA = Set.of("EXIF", "XMP ");

    /** VP8X flags: EXIF and XMP present. */
    private static final int WEBP_EXIF_FLAG = 0x08;

    private static final int WEBP_XMP_FLAG = 0x04;

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(Metadata.class);

    private Metadata() {}

    /** The image without its metadata -- the same array when there were none. */
    static byte[] strip(byte[] bytes, String contentType) {
        try {
            return switch (contentType) {
                case "image/jpeg" -> jpeg(bytes);
                case "image/png" -> png(bytes);
                case "image/webp" -> webp(bytes);
                default -> bytes;
            };
        } catch (RuntimeException malformed) {
            // Kept as it came (above) -- but said: an image that keeps its place and
            // time because of a mistake here must not pass unseen.
            log.warn("image metadata not stripped ({}, {})", contentType, malformed.getClass().getSimpleName());
            return bytes;
        }
    }

    private static byte[] jpeg(byte[] b) {
        if (b.length < 4 || (b[0] & 0xff) != 0xff || (b[1] & 0xff) != SOI) {
            return b;
        }
        int orientation = Exif.orientation(b);
        // The segments up to the image data, as [from, to, dropped?]; where the
        // orientation goes.
        List<int[]> segments = new ArrayList<>();
        int insertAt = -1;
        boolean droppedExif = false;
        boolean gainMapXmp = false;
        // A multi-picture index (APP2 "MPF"): its offsets count from where it stands to
        // the pictures after this one, so what is dropped behind it is counted.
        int mpf = -1;
        int sos;
        int at = 2;
        while (true) {
            if (at + 4 > b.length || (b[at] & 0xff) != 0xff) {
                return b;
            }
            int marker = b[at + 1] & 0xff;
            if (marker == 0xff) {
                // A fill byte before the marker, kept: nothing behind an index moves.
                segments.add(new int[] {at, at + 1, 0});
                at++;
                continue;
            }
            if (insertAt < 0 && marker != APP0) {
                insertAt = segments.size();
            }
            if (marker == SOS) {
                sos = at;
                break;
            }
            int length = ((b[at + 2] & 0xff) << 8) | (b[at + 3] & 0xff);
            int end = at + 2 + length;
            if (length < 2 || end > b.length) {
                return b;
            }
            if (mpf < 0 && marker == APP2 && startsWith(b, at + 4, "MPF\0")) {
                mpf = segments.size();
            }
            boolean metadata = marker == APP1 || marker == APP13 || marker == COM;
            if (metadata) {
                droppedExif |= marker == APP1 && startsWith(b, at + 4, "Exif\0\0");
                gainMapXmp |= marker == APP1 && startsWith(b, at + 4, XMP) && contains(b, at, end, "hdrgm:Version");
            }
            segments.add(new int[] {at, end, metadata ? 1 : 0});
            at = end;
        }

        MultiPicture pictures = mpf < 0 ? null : MultiPicture.read(b, segments.get(mpf)[0]);
        int dataEnd;
        if (mpf >= 0 && pictures == null) {
            // An index this cannot read: nothing behind it may move or go.
            for (int i = mpf + 1; i < segments.size(); i++) {
                segments.get(i)[2] = 0;
            }
            dataEnd = b.length;
        } else {
            // The image ends at its EOI, the last picture of an index where it says.
            // What comes after -- a Motion Photo's video with its GPS position, a
            // Samsung trailer -- is not part of the image.
            int end = endOfImage(b, sos);
            dataEnd = end < 0 ? b.length : end;
            if (pictures != null) {
                dataEnd = (int) Math.min(b.length, Math.max(dataEnd, pictures.end()));
            }
        }

        int droppedAfterIndex = 0;
        boolean dropped = dataEnd < b.length;
        for (int i = 0; i < segments.size(); i++) {
            int[] segment = segments.get(i);
            if (segment[2] == 1) {
                dropped = true;
                if (mpf >= 0 && i > mpf) {
                    droppedAfterIndex += segment[1] - segment[0];
                }
            }
        }
        if (!dropped) {
            return b;
        }

        var out = new ByteArrayOutputStream(b.length);
        out.write(0xff);
        out.write(SOI);
        for (int i = 0; i <= segments.size(); i++) {
            if (i == insertAt) {
                if (droppedExif && orientation != 1) {
                    out.writeBytes(orientationSegment(orientation));
                }
                if (gainMapXmp && pictures != null && pictures.count() == 2) {
                    out.writeBytes(gainMapSegment(pictures.size(1)));
                }
            }
            if (i == segments.size()) {
                break;
            }
            int[] segment = segments.get(i);
            if (segment[2] == 1) {
                continue;
            }
            if (i == mpf && pictures != null && droppedAfterIndex > 0) {
                out.writeBytes(pictures.movedBack(b, segment[0], segment[1], droppedAfterIndex));
            } else {
                out.write(b, segment[0], segment[1] - segment[0]);
            }
        }
        out.write(b, sos, dataEnd - sos);
        return out.toByteArray();
    }

    /** The namespace an XMP APP1 segment starts with. */
    private static final String XMP = "http://ns.adobe.com/xap/1.0/\0";

    /**
     * Where the image that starts with the scan at {@code sos} ends: after its EOI, or
     * {@code -1} where there is none. Between scans come segments with a length, inside
     * a scan {@code FF} is followed only by {@code 00}, a restart marker or a fill byte.
     */
    static int endOfImage(byte[] b, int sos) {
        int at = sos;
        while (at + 1 < b.length) {
            if ((b[at] & 0xff) != 0xff) {
                return -1;
            }
            int marker = b[at + 1] & 0xff;
            if (marker == EOI) {
                return at + 2;
            }
            if (marker == 0xff) {
                at++;
                continue;
            }
            if (at + 4 > b.length) {
                return -1;
            }
            int length = ((b[at + 2] & 0xff) << 8) | (b[at + 3] & 0xff);
            if (length < 2 || at + 2 + length > b.length) {
                return -1;
            }
            at += 2 + length;
            if (marker == SOS) {
                while (at + 1 < b.length) {
                    if ((b[at] & 0xff) == 0xff) {
                        int next = b[at + 1] & 0xff;
                        if (next != 0x00 && (next < 0xd0 || next > 0xd7)) {
                            break;
                        }
                        at += 2;
                    } else {
                        at++;
                    }
                }
            }
        }
        return -1;
    }

    /**
     * The XMP an Ultra HDR photo needs to show as HDR, written here and not kept: the
     * gain-map version and a directory of the primary image and its gain map. The XMP
     * the camera wrote can say anything, the place it was taken included.
     */
    static byte[] gainMapSegment(long gainMapLength) {
        String xmp = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">"
                + "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">"
                + "<rdf:Description"
                + " xmlns:Container=\"http://ns.google.com/photos/1.0/container/\""
                + " xmlns:Item=\"http://ns.google.com/photos/1.0/container/item/\""
                + " xmlns:hdrgm=\"http://ns.adobe.com/hdr-gain-map/1.0/\""
                + " hdrgm:Version=\"1.0\">"
                + "<Container:Directory><rdf:Seq>"
                + "<rdf:li rdf:parseType=\"Resource\">"
                + "<Container:Item Item:Semantic=\"Primary\" Item:Mime=\"image/jpeg\"/></rdf:li>"
                + "<rdf:li rdf:parseType=\"Resource\">"
                + "<Container:Item Item:Semantic=\"GainMap\" Item:Mime=\"image/jpeg\" Item:Length=\""
                + gainMapLength + "\"/></rdf:li>"
                + "</rdf:Seq></Container:Directory>"
                + "</rdf:Description></rdf:RDF></x:xmpmeta>";
        byte[] namespace = XMP.getBytes(StandardCharsets.US_ASCII);
        byte[] body = xmp.getBytes(StandardCharsets.UTF_8);
        int length = 2 + namespace.length + body.length;
        var out = new ByteArrayOutputStream();
        out.write(0xff);
        out.write(APP1);
        out.write(length >> 8);
        out.write(length & 0xff);
        out.writeBytes(namespace);
        out.writeBytes(body);
        return out.toByteArray();
    }

    /**
     * A multi-picture index (CIPA DC-007): a TIFF structure in an APP2 segment whose MP
     * entries give each picture's size and its offset from the TIFF header.
     *
     * @param offsetFields where each entry's offset stands in the file
     */
    record MultiPicture(int tiff, boolean little, int[] offsetFields, long[] sizes, long[] offsets) {

        private static final int MP_ENTRY = 0xb002;

        int count() {
            return sizes.length;
        }

        long size(int picture) {
            return sizes[picture];
        }

        /** Where the last picture ends, in the file. */
        long end() {
            long end = 0;
            for (int i = 0; i < offsets.length; i++) {
                if (offsets[i] != 0) {
                    end = Math.max(end, tiff + offsets[i] + sizes[i]);
                }
            }
            return end;
        }

        /** The index segment {@code [from, to)} with every picture {@code by} bytes nearer. */
        byte[] movedBack(byte[] b, int from, int to, int by) {
            byte[] segment = Arrays.copyOfRange(b, from, to);
            for (int i = 0; i < offsets.length; i++) {
                if (offsets[i] != 0) {
                    put32(segment, offsetFields[i] - from, offsets[i] - by, little);
                }
            }
            return segment;
        }

        /** The index in the APP2 segment at {@code segment}, or {@code null} where it does not add up. */
        static MultiPicture read(byte[] b, int segment) {
            int end = segment + 2 + (((b[segment + 2] & 0xff) << 8) | (b[segment + 3] & 0xff));
            int tiff = segment + 8;
            if (tiff + 8 > end) {
                return null;
            }
            boolean little;
            if (b[tiff] == 'I' && b[tiff + 1] == 'I') {
                little = true;
            } else if (b[tiff] == 'M' && b[tiff + 1] == 'M') {
                little = false;
            } else {
                return null;
            }
            long ifd = tiff + get32(b, tiff + 4, little);
            if (ifd + 2 > end) {
                return null;
            }
            int count = get16(b, (int) ifd, little);
            for (int i = 0; i < count; i++) {
                long entry = ifd + 2 + 12L * i;
                if (entry + 12 > end) {
                    return null;
                }
                if (get16(b, (int) entry, little) != MP_ENTRY) {
                    continue;
                }
                long bytes = get32(b, (int) entry + 4, little);
                long first = tiff + get32(b, (int) entry + 8, little);
                if (bytes < 16 || bytes % 16 != 0 || first + bytes > end) {
                    return null;
                }
                int pictures = (int) (bytes / 16);
                int[] fields = new int[pictures];
                long[] sizes = new long[pictures];
                long[] offsets = new long[pictures];
                for (int p = 0; p < pictures; p++) {
                    int at = (int) (first + 16L * p);
                    sizes[p] = get32(b, at + 4, little);
                    offsets[p] = get32(b, at + 8, little);
                    fields[p] = at + 8;
                    if (offsets[p] != 0 && (tiff + offsets[p] < end || tiff + offsets[p] > b.length)) {
                        return null;
                    }
                }
                return new MultiPicture(tiff, little, fields, sizes, offsets);
            }
            return null;
        }

        private static int get16(byte[] b, int at, boolean little) {
            int x = b[at] & 0xff;
            int y = b[at + 1] & 0xff;
            return little ? x | y << 8 : x << 8 | y;
        }

        private static long get32(byte[] b, int at, boolean little) {
            return (little ? le32(b, at) : be32(b, at)) & 0xffffffffL;
        }

        private static void put32(byte[] b, int at, long value, boolean little) {
            for (int i = 0; i < 4; i++) {
                int shift = little ? 8 * i : 8 * (3 - i);
                b[at + i] = (byte) (value >> shift);
            }
        }
    }

    private static boolean contains(byte[] b, int from, int to, String text) {
        byte[] needle = text.getBytes(StandardCharsets.US_ASCII);
        for (int i = from; i + needle.length <= to; i++) {
            if (Arrays.equals(b, i, i + needle.length, needle, 0, needle.length)) {
                return true;
            }
        }
        return false;
    }

    /** An APP1 EXIF block that says the orientation and nothing else. */
    static byte[] orientationSegment(int orientation) {
        byte[] tiff = {
            'M', 'M', 0, 0x2a, 0, 0, 0, 8, // big-endian TIFF, first IFD at 8
            0, 1, // one entry
            0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, (byte) orientation, 0, 0, // Orientation, SHORT, 1
            0, 0, 0, 0, // no next IFD
        };
        int length = 2 + 6 + tiff.length;
        var out = new ByteArrayOutputStream();
        out.write(0xff);
        out.write(APP1);
        out.write(length >> 8);
        out.write(length & 0xff);
        out.writeBytes("Exif\0\0".getBytes(StandardCharsets.US_ASCII));
        out.writeBytes(tiff);
        return out.toByteArray();
    }

    private static byte[] png(byte[] b) {
        // Signature, then chunks: length (4), type (4), data, CRC (4).
        var out = new ByteArrayOutputStream(b.length);
        out.write(b, 0, 8);
        boolean dropped = false;
        int at = 8;
        while (at < b.length) {
            if (at + 12 > b.length) {
                return b;
            }
            long length = be32(b, at) & 0xffffffffL;
            long end = at + 12 + length;
            if (end > b.length) {
                return b;
            }
            String type = new String(b, at + 4, 4, StandardCharsets.US_ASCII);
            if (PNG_METADATA.contains(type)) {
                dropped = true;
            } else {
                out.write(b, at, (int) (end - at));
            }
            at = (int) end;
            if (type.equals("IEND")) {
                // The image ends here. What follows is not part of it -- a second
                // file, or whatever an editor appended -- and went out with it.
                dropped |= at < b.length;
                break;
            }
        }
        return dropped ? out.toByteArray() : b;
    }

    private static byte[] webp(byte[] b) {
        // RIFF (4), size (4), WEBP (4), then chunks: FourCC (4), size (4), data, padded
        // to an even length. Only the extended layout (VP8X) holds metadata.
        if (b.length < 30 || !startsWith(b, 12, "VP8X")) {
            return b;
        }
        var out = new ByteArrayOutputStream(b.length);
        out.write(b, 0, 12);
        boolean dropped = false;
        int flags = -1;
        int at = 12;
        while (at < b.length) {
            if (at + 8 > b.length) {
                return b;
            }
            String type = new String(b, at, 4, StandardCharsets.US_ASCII);
            long size = le32(b, at + 4) & 0xffffffffL;
            long end = at + 8 + size + (size & 1);
            if (end > b.length) {
                // A last chunk without its padding byte is common enough.
                if (at + 8 + size == b.length) {
                    end = b.length;
                } else {
                    return b;
                }
            }
            if (WEBP_METADATA.contains(type)) {
                dropped = true;
            } else {
                if (type.equals("VP8X")) {
                    flags = out.size() + 8;
                }
                out.write(b, at, (int) (end - at));
            }
            at = (int) end;
        }
        if (!dropped) {
            return b;
        }
        byte[] result = out.toByteArray();
        result[flags] &= (byte) ~(WEBP_EXIF_FLAG | WEBP_XMP_FLAG);
        int riff = result.length - 8;
        result[4] = (byte) riff;
        result[5] = (byte) (riff >> 8);
        result[6] = (byte) (riff >> 16);
        result[7] = (byte) (riff >> 24);
        return result;
    }

    private static boolean startsWith(byte[] b, int at, String text) {
        byte[] expected = text.getBytes(StandardCharsets.US_ASCII);
        return at + expected.length <= b.length
                && Arrays.equals(b, at, at + expected.length, expected, 0, expected.length);
    }

    private static int be32(byte[] b, int at) {
        return ((b[at] & 0xff) << 24) | ((b[at + 1] & 0xff) << 16) | ((b[at + 2] & 0xff) << 8) | (b[at + 3] & 0xff);
    }

    private static int le32(byte[] b, int at) {
        return (b[at] & 0xff) | ((b[at + 1] & 0xff) << 8) | ((b[at + 2] & 0xff) << 16) | ((b[at + 3] & 0xff) << 24);
    }
}
