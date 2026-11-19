package de.danielkononov.hiwiski.platform.internal;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.core.io.Resource;

/**
 * What a file of the web client is called when a browser asks whether its copy is still
 * good: a name made from the file's content.
 *
 * <p><strong>Not the file's date.</strong> The image is built so that the same input
 * gives the same image, and for that every file in it carries one fixed date -- the same
 * in every release. A browser that asked "changed since that date?" was told "no" after
 * every update and went on running the web client it had loaded first, bugs included,
 * until somebody reloaded without the cache. The content's hash differs exactly when
 * the file does.
 */
final class WebClientEtags {

    private static final String ALGORITHM = "SHA-256";

    /** Enough of the hash to tell two builds of a file apart. */
    private static final int HASH_BYTES = 16;

    private static final int BUFFER_BYTES = 64 * 1024;

    /**
     * One entry per served file, so the largest one is not hashed on every request.
     * It cannot grow past the files the build holds: a made-up path is answered with
     * the application's page, which is one of them.
     */
    private final Map<String, Entry> known = new ConcurrentHashMap<>();

    /** A hash, and what the file looked like when it was taken. */
    private record Entry(long length, long modified, String etag) {}

    /** The quoted entity tag of {@code resource}. */
    String of(Resource resource) {
        try {
            String key = resource.getURL().toString();
            long length = resource.contentLength();
            long modified = resource.lastModified();
            Entry entry = known.get(key);
            // Hashed again when the file is another one than last time: a file replaced
            // under a running server must not keep the tag of the one before it.
            if (entry == null || entry.length() != length || entry.modified() != modified) {
                entry = new Entry(length, modified, hash(resource));
                known.put(key, entry);
            }
            return entry.etag();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static String hash(Resource resource) throws IOException {
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance(ALGORITHM);
        } catch (NoSuchAlgorithmException e) {
            // Every Java runtime has to provide SHA-256.
            throw new IllegalStateException(e);
        }
        try (InputStream in = new DigestInputStream(resource.getInputStream(), digest)) {
            byte[] buffer = new byte[BUFFER_BYTES];
            while (in.read(buffer) != -1) {
                // Reading is what feeds the digest.
            }
        }
        return '"' + HexFormat.of().formatHex(digest.digest(), 0, HASH_BYTES) + '"';
    }
}
