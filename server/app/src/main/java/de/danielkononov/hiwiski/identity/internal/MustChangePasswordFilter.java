package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.ApiErrorResponses;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Locks the session as long as a new password is missing.
 *
 * <p>"As long as {@code mustChangePassword} is set, the session is restricted: it may do
 * exactly {@code POST /api/v1/auth/password} and nothing else. A state in which the user
 * can use the app and swipe the prompt away would not be a prompt."
 *
 * <p>This lives here and not in the client: the client shows the screen, but the server
 * has to enforce it -- otherwise a second device is enough.
 */
@Component
class MustChangePasswordFilter extends OncePerRequestFilter {

    private static final String PASSWORD_PATH = "/api/v1/auth/password";
    private static final String SESSION_PATH = "/api/v1/auth/session";
    private static final String LOGOUT_PATH = "/api/v1/auth/logout";
    private static final String HANDSHAKE_PATH = "/api/v1/handshake";
    private static final String LOGIN_PATH = "/api/v1/auth/login";

    private final ApiErrorResponses errors;

    MustChangePasswordFilter(ApiErrorResponses errors) {
        this.errors = errors;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        boolean blocked =
                CurrentUser.current()
                        .map(CurrentUser.Principal::mustChangePassword)
                        .orElse(false);

        if (blocked && !allowed(request)) {
            errors.write(response, org.springframework.http.HttpStatus.FORBIDDEN, "auth.password_change_required");
            return;
        }
        chain.doFilter(request, response);
    }

    /**
     * What the restricted session may do.
     *
     * <p>Besides the password change itself, two more things: fetching the session --
     * otherwise the app would not know after a restart why it is stuck -- and logging
     * out. Neither reveals any content.
     *
     * <p>Plus handshake and login: those are public anyway, but the app sends its token
     * with every request. Without this exception, the handshake would already fail at
     * startup, the app would consider the server unreachable and show the login screen --
     * and the login, too, would run into {@code auth.password_change_required} with the
     * old token. The screen for changing the password could never be reached.
     */
    private static boolean allowed(HttpServletRequest request) {
        String path = request.getRequestURI();
        return PASSWORD_PATH.equals(path)
                || SESSION_PATH.equals(path)
                || LOGOUT_PATH.equals(path)
                || HANDSHAKE_PATH.equals(path)
                || LOGIN_PATH.equals(path);
    }
}
