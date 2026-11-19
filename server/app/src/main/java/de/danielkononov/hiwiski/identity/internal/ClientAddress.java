package de.danielkononov.hiwiski.identity.internal;

import de.danielkononov.hiwiski.platform.CurrentRequest;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.HexFormat;

/**
 * Where a request comes from, as the throttles count it.
 *
 * <p>The address is the one Tomcat settled on: behind Caddy that is the client's, from
 * {@code X-Forwarded-For} -- but only when the request came from a trusted proxy
 * ({@code server.forward-headers-strategy: native}). A client that
 * reaches the server directly cannot claim a different address with the header.
 *
 * <p>An IPv6 client counts by its {@code /64}: a single connection usually holds a whole
 * one, and a new address from it per attempt must not be a new budget.
 */
final class ClientAddress {

    private ClientAddress() {}

    /** The current request's client. */
    static String current() {
        return of(CurrentRequest.get().getRemoteAddr());
    }

    static String of(String remoteAddress) {
        if (remoteAddress == null || remoteAddress.isBlank()) {
            return "";
        }
        // Only a literal from Tomcat gets here; parsing it does not ask DNS.
        if (!remoteAddress.contains(":")) {
            return remoteAddress;
        }
        try {
            InetAddress address = InetAddress.getByName(remoteAddress);
            if (address instanceof Inet6Address) {
                byte[] bytes = address.getAddress();
                return HexFormat.of().formatHex(bytes, 0, 8) + "::/64";
            }
            return address.getHostAddress();
        } catch (UnknownHostException e) {
            return remoteAddress;
        }
    }
}
