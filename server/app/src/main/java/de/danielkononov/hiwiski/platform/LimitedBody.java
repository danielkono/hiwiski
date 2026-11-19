package de.danielkononov.hiwiski.platform;

import java.io.IOException;
import java.io.InputStream;
import java.net.http.HttpResponse;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Optional;

/**
 * Reads a foreign response's body only up to a limit.
 *
 * <p>{@code BodyHandlers.ofString()} buffers the whole body before anyone can look at its
 * size: an address that serves several gigabytes -- or never stops -- fills the heap
 * until the server falls over, for the whole family. And {@code String.length()} counts
 * characters, not bytes. Here the {@code Content-Length} is checked first, and then no
 * more than one byte past the limit is read.
 *
 * <p>Next to {@link OutboundUrls}: whatever the server fetches from outside goes through
 * both.
 */
public final class LimitedBody {

    private LimitedBody() {}

    /**
     * The body as text, or empty if it is larger than {@code maxBytes}. Closes the body
     * either way.
     *
     * @param response a response with the body as a stream ({@code BodyHandlers.ofInputStream()})
     */
    public static Optional<String> read(HttpResponse<InputStream> response, int maxBytes) throws IOException {
        try (InputStream body = response.body()) {
            long declared = response.headers().firstValueAsLong("content-length").orElse(-1);
            if (declared > maxBytes) {
                return Optional.empty();
            }
            byte[] bytes = body.readNBytes(maxBytes + 1);
            if (bytes.length > maxBytes) {
                return Optional.empty();
            }
            return Optional.of(new String(bytes, charsetOf(response)));
        }
    }

    /** Closes a body that is not going to be read -- a redirect, an error. */
    public static void discard(HttpResponse<InputStream> response) {
        try {
            response.body().close();
        } catch (IOException ignored) {
            // Nothing to keep from a body nobody reads.
        }
    }

    private static Charset charsetOf(HttpResponse<?> response) {
        return response.headers().firstValue("content-type").stream()
                .flatMap(type -> java.util.Arrays.stream(type.split(";")))
                .map(String::trim)
                .filter(part -> part.toLowerCase(Locale.ROOT).startsWith("charset="))
                .map(part -> part.substring("charset=".length()).replace("\"", ""))
                .findFirst()
                .flatMap(name -> {
                    try {
                        return Optional.of(Charset.forName(name));
                    } catch (RuntimeException unknown) {
                        return Optional.empty();
                    }
                })
                .orElse(StandardCharsets.UTF_8);
    }
}
