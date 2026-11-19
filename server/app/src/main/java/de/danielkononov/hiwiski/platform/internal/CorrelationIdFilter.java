package de.danielkononov.hiwiski.platform.internal;

import de.danielkononov.hiwiski.platform.CorrelationId;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.HexFormat;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Gives every request a short identifier and puts it into the MDC and the response.
 *
 * <p>Short and not a UUID, because it gets read out over the phone.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class CorrelationIdFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        String incoming = request.getHeader(CorrelationId.HEADER);
        String id = (incoming != null && !incoming.isBlank()) ? shorten(incoming) : generate();

        CorrelationId.set(id);
        MDC.put(CorrelationId.MDC_KEY, id);
        response.setHeader(CorrelationId.HEADER, id);
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove(CorrelationId.MDC_KEY);
            CorrelationId.clear();
        }
    }

    private static String generate() {
        byte[] bytes = new byte[4];
        ThreadLocalRandom.current().nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }

    /** Foreign identifiers are truncated so nothing arbitrary ends up in the log. */
    private static String shorten(String value) {
        String cleaned = value.replaceAll("[^A-Za-z0-9-]", "");
        return cleaned.length() <= 36 ? cleaned : cleaned.substring(0, 36);
    }
}
