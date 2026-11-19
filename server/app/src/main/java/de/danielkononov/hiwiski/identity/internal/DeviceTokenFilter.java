package de.danielkononov.hiwiski.identity.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;

import de.danielkononov.hiwiski.identity.CurrentUser;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.jooq.DSLContext;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Takes the opaque device token from the header and turns it into a session.
 *
 * <p>No JWT: a JWT cannot be revoked before it expires, but a lost phone has to be
 * locked out immediately. The token is therefore a random value, stored on
 * the server only as a hash, and a revocation takes effect on the next call -- because
 * this filter no longer finds it.
 */
@Component
class DeviceTokenFilter extends OncePerRequestFilter {

    private static final String PREFIX = "Bearer ";

    private final DeviceRepository devices;
    private final Secrets secrets;
    private final DSLContext db;

    DeviceTokenFilter(DeviceRepository devices, Secrets secrets, DSLContext db) {
        this.devices = devices;
        this.secrets = secrets;
        this.db = db;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(PREFIX)) {
            authenticate(header.substring(PREFIX.length()).trim());
        }
        try {
            chain.doFilter(request, response);
        } finally {
            SecurityContextHolder.clearContext();
        }
    }

    private void authenticate(String token) {
        if (token.isEmpty()) {
            return;
        }
        devices.findByTokenHash(secrets.hashToken(token))
                .ifPresent(
                        device -> {
                            var member =
                                    db.select(MEMBER.IS_ADMIN, MEMBER.MUST_CHANGE_PASSWORD, MEMBER.DISABLED_AT)
                                            .from(MEMBER)
                                            .where(MEMBER.ID.eq(device.memberId()))
                                            .fetchOne();
                            // A disabled member has no session -- not even with a
                            // token that still looks valid.
                            if (member == null || member.get(MEMBER.DISABLED_AT) != null) {
                                return;
                            }
                            var principal =
                                    new CurrentUser.Principal(
                                            device.memberId(),
                                            device.id(),
                                            member.get(MEMBER.IS_ADMIN),
                                            member.get(MEMBER.MUST_CHANGE_PASSWORD));
                            SecurityContextHolder.getContext()
                                    .setAuthentication(
                                            UsernamePasswordAuthenticationToken.authenticated(
                                                    principal, null, List.of()));
                            devices.touch(device.id());
                        });
    }
}
