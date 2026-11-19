package de.danielkononov.hiwiski.platform.internal;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Caps the body of a JSON request.
 *
 * <p>Uploads have their limit in {@code spring.servlet.multipart}; a JSON body had none and
 * was read into memory whole -- a sync push of any size, from any signed-in member.
 *32 MiB is far above what the app sends: 50 mutations at a time,
 * and an ICS file to import is itself capped at 8 MiB.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
class JsonBodyLimitFilter extends OncePerRequestFilter {

    static final long MAX_BYTES = 32L * 1024 * 1024;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String contentType = request.getContentType();
        if (contentType == null || !contentType.toLowerCase().startsWith(MediaType.APPLICATION_JSON_VALUE)) {
            chain.doFilter(request, response);
            return;
        }
        if (request.getContentLengthLong() > MAX_BYTES) {
            response.setStatus(HttpServletResponse.SC_REQUEST_ENTITY_TOO_LARGE);
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write("{\"code\":\"request.too_large\"}");
            return;
        }
        // Without a length (chunked), the stream itself stops at the limit; reading on
        // fails, and the request ends as unreadable.
        chain.doFilter(new Limited(request), response);
    }

    private static final class Limited extends HttpServletRequestWrapper {

        Limited(HttpServletRequest request) {
            super(request);
        }

        @Override
        public ServletInputStream getInputStream() throws IOException {
            ServletInputStream inner = super.getInputStream();
            return new ServletInputStream() {
                private long read;

                private void count(long bytes) throws IOException {
                    read += bytes;
                    if (read > MAX_BYTES) {
                        throw new IOException("request body larger than " + MAX_BYTES + " bytes");
                    }
                }

                @Override
                public int read() throws IOException {
                    int value = inner.read();
                    if (value >= 0) {
                        count(1);
                    }
                    return value;
                }

                @Override
                public int read(byte[] buffer, int offset, int length) throws IOException {
                    int count = inner.read(buffer, offset, length);
                    if (count > 0) {
                        count(count);
                    }
                    return count;
                }

                @Override
                public boolean isFinished() {
                    return inner.isFinished();
                }

                @Override
                public boolean isReady() {
                    return inner.isReady();
                }

                @Override
                public void setReadListener(ReadListener listener) {
                    inner.setReadListener(listener);
                }
            };
        }
    }
}
