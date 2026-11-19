package de.danielkononov.hiwiski.identity.internal;

import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.HeadersConfigurer;
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter.ReferrerPolicy;

/**
 * What the browser may do with the web client this server serves.
 *
 * <p>Sent by the server, not by a proxy: a family's server is reached through its own
 * Caddy, a NAS's proxy or none at all, and the web client handles passwords and the
 * device token in every case. The policy is the demo's (deploy/demo-image/Caddyfile),
 * which runs the same build without a server:
 *
 * <ul>
 *   <li>{@code 'wasm-unsafe-eval'} for CanvasKit and the database ({@code sqlite3.wasm}),
 *       {@code blob:} for the web workers Drift starts, {@code data:} for images the app
 *       draws itself. {@code style-src 'unsafe-inline'} for the engine's own styles.
 *   <li>Nothing from anywhere else and no camera: the client has no scanner of its
 *       own -- an invitation's QR code is read by the phone's camera app.
 * </ul>
 *
 * <p>Spring Security's defaults stay on next to it: {@code X-Frame-Options: DENY},
 * {@code nosniff}, no caching of API responses.
 */
final class SecurityHeaders {

    static final String CONTENT_SECURITY_POLICY = String.join(
            "; ",
            "default-src 'self'",
            "script-src 'self' 'wasm-unsafe-eval'",
            "worker-src 'self' blob:",
            "style-src 'self' 'unsafe-inline'",
            "img-src 'self' data: blob:",
            "font-src 'self' data:",
            "media-src 'self' blob:",
            "connect-src 'self'",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "base-uri 'self'",
            "form-action 'none'");

    static final String PERMISSIONS_POLICY = "camera=(), microphone=(), geolocation=()";

    private SecurityHeaders() {}

    static void configure(HeadersConfigurer<HttpSecurity> headers) {
        headers.contentSecurityPolicy(csp -> csp.policyDirectives(CONTENT_SECURITY_POLICY))
                .referrerPolicy(referrer -> referrer.policy(ReferrerPolicy.NO_REFERRER))
                .permissionsPolicyHeader(permissions -> permissions.policy(PERMISSIONS_POLICY));
    }
}
