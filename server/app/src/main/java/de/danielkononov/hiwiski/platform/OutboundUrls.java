package de.danielkononov.hiwiski.platform;

import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Checks whether the server may fetch a foreign address.
 *
 * <p><strong>No outbound fetch into the local network.</strong> Recipe import and ICS
 * subscription go through the server because CORS stops the browser from doing it. That
 * makes the server a tool that can fetch arbitrary addresses — and that includes the
 * router.
 *
 * <p>What gets checked is the <strong>resolved IP</strong> and not the name, and that
 * <strong>before and after every redirect</strong>. A name pointing to 127.0.0.1 looks
 * harmless; so does a redirect there. And on <strong>every</strong>
 * lookup of the name, not only the first: the HTTP client resolves it again when it
 * connects, and a DNS server answering a public IP for the check and 127.0.0.1 for the
 * connection got past a check made once.
 *
 * <p>This class lives in {@code platform} because two domain modules need it —
 * {@code calendar} for subscriptions and {@code wiki} for the recipe import. Written
 * twice, it would be tested one time too few.
 */
public final class OutboundUrls {

    private OutboundUrls() {}

    private static final List<String> ALLOWED_SCHEMES = List.of("http", "https");

    /**
     * Throws if this address may not be fetched.
     *
     * @return the checked address
     */
    public static URI require(String url) {
        URI uri;
        try {
            uri = URI.create(url.trim());
        } catch (RuntimeException e) {
            throw HiwiskiException.invalid("net.url_invalid", "url", url);
        }
        if (uri.getScheme() == null || !ALLOWED_SCHEMES.contains(uri.getScheme().toLowerCase())) {
            throw HiwiskiException.invalid("net.url_scheme_not_allowed", "url", url);
        }
        if (uri.getHost() == null || uri.getHost().isBlank()) {
            throw HiwiskiException.invalid("net.url_invalid", "url", url);
        }
        requirePublic(uri.getHost());
        return uri;
    }

    /**
     * The names the server was asked to fetch from. Every later lookup of one of them --
     * the HTTP client resolves the name again on its own -- goes through the same check
     * ({@link OutboundResolverProvider}).
     */
    private static final Set<String> GUARDED = ConcurrentHashMap.newKeySet();

    /** Whether lookups of this name must not return a private address. */
    static boolean guarded(String host) {
        return host != null && GUARDED.contains(host.toLowerCase(Locale.ROOT));
    }

    /** The same check after a redirect. */
    public static void requirePublic(String host) {
        InetAddress[] addresses;
        try {
            addresses = InetAddress.getAllByName(host);
        } catch (UnknownHostException e) {
            throw HiwiskiException.invalid("net.host_unknown", "host", host);
        }
        for (InetAddress address : addresses) {
            if (isPrivate(address)) {
                throw HiwiskiException.invalid("net.address_not_allowed", "host", host);
            }
        }
        // From here on no lookup of this name may answer with a private address -- not
        // the one the HTTP client makes when it connects, after a DNS answer with TTL 0
        // changed to 127.0.0.1 in between. Only a name that passed: guarding "localhost"
        // or the database's host because someone typed it would cut the server off from
        // its own database.
        GUARDED.add(host.toLowerCase(Locale.ROOT));
    }

    /**
     * Private ranges, loopback, link-local and metadata addresses.
     *
     * <p>The last one is the one nobody thinks of: at every cloud provider,
     * {@code 169.254.169.254} is the way to the machine's credentials. It falls under
     * link-local here — but it is still named explicitly, so that nobody "cleans up" the
     * line later.
     */
    static boolean isPrivate(InetAddress address) {
        return address.isAnyLocalAddress()
                || address.isLoopbackAddress()
                || address.isLinkLocalAddress()
                || address.isSiteLocalAddress()
                || address.isMulticastAddress()
                || isUniqueLocalIpv6(address)
                || isCarrierGradeNat(address);
    }

    /** {@code fc00::/7} — the IPv6 counterpart to 10.0.0.0/8 and friends. */
    private static boolean isUniqueLocalIpv6(InetAddress address) {
        byte[] bytes = address.getAddress();
        return bytes.length == 16 && (bytes[0] & 0xFE) == 0xFC;
    }

    /** {@code 100.64.0.0/10} — rare on home networks, the uplink at some providers. */
    private static boolean isCarrierGradeNat(InetAddress address) {
        byte[] bytes = address.getAddress();
        return bytes.length == 4
                && (bytes[0] & 0xFF) == 100
                && (bytes[1] & 0xC0) == 0x40;
    }
}
