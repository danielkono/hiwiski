package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.IntegrationTest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * After an update the browser gets the new web client.
 *
 * <p>The files of every release carry the same date. While the server let the browser
 * ask "changed since that date?", the answer after an update was "no", and the browser
 * went on running the web client it had loaded first.
 */
@IntegrationTest
class WebClientCachingIT {

    /** A file of the web client, as far as the server can tell (test resources). */
    private static final String FILE = "/web-client-probe.txt";

    @Autowired RestTestClient rest;

    private HttpHeaders get(HttpStatus expected, String header, String value) {
        var request = rest.get().uri(FILE);
        if (header != null) request = request.header(header, value);
        return request.exchange().expectStatus().isEqualTo(expected).returnResult().getResponseHeaders();
    }

    @Test
    void theBrowserAsksEveryTimeAndByContent() {
        var headers = get(HttpStatus.OK, null, null);

        assertThat(headers.getCacheControl()).isEqualTo("no-cache");
        assertThat(headers.getETag()).isNotBlank();
        // No date beside it: a browser prefers the tag, but one that only holds a date
        // would ask by it.
        assertThat(headers.getFirst(HttpHeaders.LAST_MODIFIED)).isNull();
    }

    @Test
    void anUnchangedFileIsNotSentAgain() {
        var etag = get(HttpStatus.OK, null, null).getETag();

        get(HttpStatus.NOT_MODIFIED, HttpHeaders.IF_NONE_MATCH, etag);
    }

    @Test
    void aCopyOfAnotherReleaseIsReplaced() {
        get(HttpStatus.OK, HttpHeaders.IF_NONE_MATCH, "\"the-tag-of-another-release\"");
    }

    /**
     * A browser that loaded the web client from a server that still answered by date
     * holds no tag, only that date, and asks by it. It has to get the file: this is
     * what frees it from the old web client without anybody clearing a cache. The date
     * here is later than any file's, so answering by date would say "not modified".
     */
    @Test
    void aCopyHeldByDateIsReplaced() {
        get(HttpStatus.OK, HttpHeaders.IF_MODIFIED_SINCE, "Fri, 01 Jan 2100 00:00:00 GMT");
    }
}
