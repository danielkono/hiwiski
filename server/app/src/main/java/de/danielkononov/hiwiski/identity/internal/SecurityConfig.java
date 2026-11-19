package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.ApiErrorResponses;
import org.springframework.boot.autoconfigure.condition.ConditionalOnWebApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * The HTTP scaffolding of security.
 *
 * <p>There is <em>no</em> domain permission check here. Who may see what is decided by
 * the share in the {@code access} module. This class only defines which paths are
 * reachable without login at all -- and plugs in the two filters that turn a device
 * token into a session and enforce a forced password change.
 */
@Configuration
// Only with a web server: a maintenance command starts without one (CommandModeIT).
@ConditionalOnWebApplication
class SecurityConfig {

    private final ApiErrorResponses apiErrors;
    private final DeviceTokenFilter deviceTokens;
    private final MustChangePasswordFilter mustChangePassword;

    SecurityConfig(
            ApiErrorResponses apiErrors,
            DeviceTokenFilter deviceTokens,
            MustChangePasswordFilter mustChangePassword) {
        this.apiErrors = apiErrors;
        this.deviceTokens = deviceTokens;
        this.mustChangePassword = mustChangePassword;
    }

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .exceptionHandling(
                        handling ->
                                handling
                                        .authenticationEntryPoint(apiErrors)
                                        .accessDeniedHandler(apiErrors))
                // No cookies, no session: the client sends its opaque device token with
                // every request. That makes CSRF moot.
                .csrf(csrf -> csrf.disable())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .logout(logout -> logout.disable())
                .headers(SecurityHeaders::configure)
                .addFilterBefore(deviceTokens, UsernamePasswordAuthenticationFilter.class)
                .addFilterAfter(mustChangePassword, DeviceTokenFilter.class)
                .authorizeHttpRequests(
                        auth ->
                                auth
                                        // Reachable before any login.
                                        .requestMatchers(HttpMethod.GET, "/api/v1/handshake")
                                        .permitAll()
                                        .requestMatchers(HttpMethod.POST, "/api/v1/setup")
                                        .permitAll()
                                        // Restoring on a fresh server: the setup code
                                        // in a header instead of a sign-in.
                                        .requestMatchers(HttpMethod.POST, "/api/v1/setup/uploads", "/api/v1/setup/uploads/*/*")
                                        .permitAll()
                                        .requestMatchers(HttpMethod.POST, "/api/v1/auth/login")
                                        .permitAll()
                                        // The preview of an invitation and its
                                        // redemption: whoever joins has no account yet.
                                        .requestMatchers(HttpMethod.GET, "/api/v1/invitations/*")
                                        .permitAll()
                                        .requestMatchers(HttpMethod.POST, "/api/v1/invitations/*/redeem")
                                        .permitAll()
                                        // The stream authenticates via its short-lived
                                        // ticket: `EventSource` in the browser cannot
                                        // send a header.
                                        .requestMatchers(HttpMethod.GET, "/api/v1/events")
                                        .permitAll()
                                        // The wall tablet board under its own address.
                                        // **No login, does not expire, revocable**:
                                        // a wall tablet as a full account would
                                        // mean a token without expiry in the keychain,
                                        // an app that never logs out, and no way out of
                                        // full screen without a keyboard. The token in
                                        // the path is the secret; what it may see is
                                        // decided by the board's owner.
                                        .requestMatchers(HttpMethod.GET, "/api/v1/boards/*")
                                        .permitAll()
                                        .requestMatchers(HttpMethod.POST, "/api/v1/boards/*/ticket")
                                        .permitAll()
                                        // What the tiles show, in the owner's name.
                                        .requestMatchers(HttpMethod.GET, "/api/v1/boards/*/content")
                                        .permitAll()
                                        .requestMatchers("/actuator/health/**")
                                        .permitAll()
                                        // The served web client is a static bundle.
                                        // What it may *see* is decided by the API, not
                                        // by which files it can load -- a list of
                                        // individual paths here would be a list that
                                        // gets forgotten with the next asset. That is
                                        // exactly what happened with `sqlite3.wasm`,
                                        // which Drift needs in the browser.
                                        .requestMatchers(HttpMethod.GET, "/api/**")
                                        .authenticated()
                                        .requestMatchers(HttpMethod.GET, "/**")
                                        .permitAll()
                                        // A monitor or a link preview asks with HEAD;
                                        // it got "sign in first" for the sign-in page.
                                        .requestMatchers(HttpMethod.HEAD, "/api/**")
                                        .authenticated()
                                        .requestMatchers(HttpMethod.HEAD, "/**")
                                        .permitAll()
                                        .anyRequest()
                                        .authenticated());
        return http.build();
    }

    /**
     * A request the firewall refuses -- a doubled slash, a semicolon in the path -- is
     * answered like any other invalid one: a code, not the container's own page.
     */
    @Bean
    org.springframework.security.web.firewall.RequestRejectedHandler requestRejectedHandler() {
        return (request, response, rejected) ->
                apiErrors.write(response, org.springframework.http.HttpStatus.BAD_REQUEST, "request.invalid");
    }
}
