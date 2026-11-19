package de.danielkononov.hiwiski.identity;

import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.Optional;
import java.util.UUID;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * Who is making the current request.
 *
 * <p>The way to the session without every domain module having to know the security
 * chain. Login itself is the business of {@code identity}; everything below it is
 * invisible.
 */
public final class CurrentUser {

    private CurrentUser() {}

    /**
     * The current session.
     *
     * <p>Throws if there is none. That is not a special case but a programming error:
     * every path except handshake, login, invitation preview and redemption is
     * authenticated.
     */
    public static Principal require() {
        return current()
                .orElseThrow(() -> new HiwiskiException(
                        org.springframework.http.HttpStatus.UNAUTHORIZED, "auth.required", java.util.Map.of()));
    }

    public static Optional<Principal> current() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !(authentication.getPrincipal() instanceof Principal principal)) {
            return Optional.empty();
        }
        return Optional.of(principal);
    }

    public static UUID requireMemberId() {
        return require().memberId();
    }

    /**
     * The session of a device.
     *
     * @param memberId who
     * @param deviceId from which device
     * @param admin may manage the server -- settings, members, backup, update. In the
     *     domain, the administrator has <strong>no</strong> special rights.
     * @param mustChangePassword while this is set, the session may do exactly
     *     {@code POST /api/v1/auth/password} and nothing else
     */
    public record Principal(UUID memberId, UUID deviceId, boolean admin, boolean mustChangePassword) {

        /** Throws if this call is reserved for the administrator. */
        public void requireAdmin() {
            if (!admin) {
                throw HiwiskiException.forbidden("identity.admin_required");
            }
        }
    }
}
