package de.danielkononov.hiwiski.platform;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * The request being answered -- read when it is needed, not injected.
 *
 * <p>A controller that took the request in its constructor could not be created without
 * a web server, and a maintenance command ({@code hiwiski reset-admin-password}) runs
 * without one: it failed before it got to do anything. Called outside a request, this
 * throws, as an injected request would on its first use.
 */
public final class CurrentRequest {

    private CurrentRequest() {}

    public static HttpServletRequest get() {
        return ((ServletRequestAttributes) RequestContextHolder.currentRequestAttributes()).getRequest();
    }
}
