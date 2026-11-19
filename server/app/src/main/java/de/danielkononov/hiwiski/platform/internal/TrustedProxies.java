package de.danielkononov.hiwiski.platform.internal;

import java.net.Inet6Address;
import java.net.InetAddress;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;
import org.apache.catalina.valves.RemoteIpValve;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.tomcat.servlet.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.core.Ordered;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * Whose {@code X-Forwarded-For} and {@code X-Forwarded-Proto} the server believes.
 *
 * <p>Tomcat applies the headers only from an internal proxy. Spring Boot's default for
 * that is every private, loopback and link-local range -- which on a server run without
 * Caddy let any device on the home network name a new address with each request and
 * step around the sign-in, setup-code and invitation budgets per address. Now only
 * loopback is trusted, plus the addresses named in {@code HIWISKI_TRUSTED_PROXIES}:
 * the shipped compose files pin Caddy's address and name exactly that one, so the
 * server believes Caddy and nothing else on its network.
 *
 * <p>Addresses, not names: a name would have to be looked up, and Caddy's address changes
 * when its container is recreated -- the compose files fix it instead. An operator who
 * needs more sets {@code SERVER_TOMCAT_REMOTEIP_INTERNALPROXIES} (a regular expression
 * over the proxy's address); when that is not empty it is used as it is. Empty -- the
 * compose files pass it through empty when the {@code .env} has none -- means this list,
 * not Tomcat's "trust nobody", which would take every request behind Caddy for
 * cleartext.
 */
@Component
class TrustedProxies implements WebServerFactoryCustomizer<TomcatServletWebServerFactory>, Ordered {

    /** Loopback, as Tomcat writes the address: a process on the server's own machine. */
    static final String LOOPBACK = "127\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}|0:0:0:0:0:0:0:1|::1";

    private final String addresses;
    private final String operatorPattern;

    TrustedProxies(
            @Value("${hiwiski.trusted-proxies:}") String addresses,
            @Value("${server.tomcat.remoteip.internal-proxies:}") String operatorPattern) {
        this.addresses = addresses;
        this.operatorPattern = operatorPattern;
    }

    @Override
    public void customize(TomcatServletWebServerFactory factory) {
        String pattern = pattern();
        factory.getEngineValves().stream()
                .filter(RemoteIpValve.class::isInstance)
                .map(RemoteIpValve.class::cast)
                .forEach(valve -> valve.setInternalProxies(pattern));
    }

    /** After Spring Boot's own customizer, which adds the valve with its default. */
    @Override
    public int getOrder() {
        return Ordered.LOWEST_PRECEDENCE;
    }

    /** The regular expression Tomcat matches a peer's address against. */
    String pattern() {
        if (StringUtils.hasText(operatorPattern)) {
            return operatorPattern;
        }
        return pattern(addresses);
    }

    /**
     * Loopback and each listed address, literally.
     *
     * @throws IllegalStateException for an entry that is not an IP address -- a typo
     *     stops the start instead of trusting nobody, or the wrong host, in silence
     */
    static String pattern(String addresses) {
        List<String> parts = new ArrayList<>();
        parts.add(LOOPBACK);
        if (addresses != null) {
            for (String entry : addresses.split("[,\\s]+")) {
                if (!entry.isEmpty()) {
                    forms(entry).forEach(form -> parts.add(Pattern.quote(form)));
                }
            }
        }
        return String.join("|", parts);
    }

    /** The address as given and as Tomcat writes it ({@code fd00:0:0:0:0:0:0:2}). */
    private static Set<String> forms(String entry) {
        InetAddress address;
        try {
            // A literal only: ofLiteral never asks DNS.
            address = InetAddress.ofLiteral(entry);
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException(
                    "HIWISKI_TRUSTED_PROXIES holds \"" + entry + "\", which is not an IP address", e);
        }
        Set<String> forms = new LinkedHashSet<>(Arrays.asList(entry, address.getHostAddress()));
        if (address instanceof Inet6Address) {
            forms.add(address.getHostAddress().replaceFirst("%.*$", ""));
        }
        return forms;
    }
}
