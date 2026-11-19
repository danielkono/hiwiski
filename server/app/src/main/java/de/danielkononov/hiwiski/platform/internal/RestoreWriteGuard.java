package de.danielkononov.hiwiski.platform.internal;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.RestoreInProgress;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Set;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Nothing is written while a backup is restored: every change is
 * {@code 503 instance.restoring} with {@code Retry-After}, and the app tries again once
 * it is done. Reading goes on -- it sees the state from before until the swap commits.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 2)
class RestoreWriteGuard extends OncePerRequestFilter {

    static final int RETRY_AFTER_SECONDS = 5;

    private static final Set<String> READING = Set.of("GET", "HEAD", "OPTIONS");

    /**
     * POSTs that change nothing: a ticket for the event stream. Refused, an app that
     * connected while the restore ran never heard of it -- the stream is how it learns.
     */
    private static final java.util.regex.Pattern TICKETS =
            java.util.regex.Pattern.compile("/api/v1/(events|boards/[^/]+)/ticket");

    private final RestoreInProgress restore;

    RestoreWriteGuard(RestoreInProgress restore) {
        this.restore = restore;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (restore.since().isEmpty()
                || READING.contains(request.getMethod())
                || !request.getRequestURI().startsWith("/api/")
                || TICKETS.matcher(request.getRequestURI()).matches()) {
            chain.doFilter(request, response);
            return;
        }
        response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
        response.setHeader(HttpHeaders.RETRY_AFTER, String.valueOf(RETRY_AFTER_SECONDS));
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter()
                .write("{\"code\":\"instance.restoring\",\"params\":{\"" + HiwiskiException.RETRY_AFTER_SECONDS
                        + "\":\"" + RETRY_AFTER_SECONDS + "\"}}");
    }
}
