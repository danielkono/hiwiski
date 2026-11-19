package de.danielkononov.hiwiski.calendar.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.LimitedBody;
import de.danielkononov.hiwiski.platform.OutboundUrls;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.springframework.stereotype.Component;

/**
 * Fetches a foreign file — and only from where it is allowed.
 *
 * <p>Redirects are followed <strong>by hand</strong> so that every target is checked
 * again. A server answering `302` to `http://192.168.1.1/` would otherwise be exactly
 * the path the check is meant to block.
 */
@Component
class IcsFetcher {

    /** Enough for a holiday calendar, too little for an attack on the disk. */
    private static final int MAX_BYTES = 8 * 1024 * 1024;

    private static final int MAX_REDIRECTS = 5;

    private final HttpClient http = HttpClient.newBuilder()
            // NEVER, not NORMAL: otherwise the client follows the redirect itself, and
            // the check sees only the first address.
            .followRedirects(HttpClient.Redirect.NEVER)
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    String fetch(String url) {
        URI uri = OutboundUrls.require(url);

        for (int redirect = 0; redirect <= MAX_REDIRECTS; redirect++) {
            HttpResponse<java.io.InputStream> response;
            try {
                response = http.send(
                        HttpRequest.newBuilder(uri)
                                .timeout(Duration.ofSeconds(30))
                                .header("Accept", "text/calendar, text/plain;q=0.8, */*;q=0.5")
                                .header("User-Agent", "hiwiski")
                                .GET()
                                .build(),
                        HttpResponse.BodyHandlers.ofInputStream());
            } catch (java.io.IOException e) {
                throw HiwiskiException.invalid("calendar.subscription_unreachable", "url", url);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw HiwiskiException.invalid("calendar.subscription_unreachable", "url", url);
            }

            int status = response.statusCode();
            if (status != 200) {
                LimitedBody.discard(response);
            }
            if (status >= 300 && status < 400) {
                String location = response.headers().firstValue("location").orElse(null);
                if (location == null) {
                    throw HiwiskiException.invalid("calendar.subscription_unreachable", "url", url);
                }
                // Before AND after every redirect, against the resolved IP.
                uri = OutboundUrls.require(uri.resolve(location).toString());
                continue;
            }
            if (status != 200) {
                throw HiwiskiException.invalid("calendar.subscription_http_error", "status", status);
            }
            try {
                return LimitedBody.read(response, MAX_BYTES)
                        .orElseThrow(() -> HiwiskiException.invalid("calendar.subscription_too_large"));
            } catch (java.io.IOException e) {
                throw HiwiskiException.invalid("calendar.subscription_unreachable", "url", url);
            }
        }
        throw HiwiskiException.invalid("calendar.subscription_too_many_redirects", "url", url);
    }
}
