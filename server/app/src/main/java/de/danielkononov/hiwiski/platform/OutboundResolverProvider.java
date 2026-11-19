package de.danielkononov.hiwiski.platform;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.net.spi.InetAddressResolver;
import java.net.spi.InetAddressResolverProvider;
import java.util.List;
import java.util.stream.Stream;

/**
 * Name resolution for the whole JVM: as the system does it, except that a name the
 * server was asked to fetch from never resolves to a private address
 * ({@link OutboundUrls}).
 *
 * <p>The HTTP clients of the recipe import and the calendar subscriptions resolve a name
 * again when they connect, after {@link OutboundUrls} checked it. Checked once, a DNS
 * server could answer with a public address for the check and with the router's or the
 * cloud metadata address for the connection. Here every lookup of such a name is checked
 * -- and only those: the database's host and everything else resolve as before.
 *
 * <p>Registered in {@code META-INF/services}; the JDK loads it on the first lookup.
 */
public final class OutboundResolverProvider extends InetAddressResolverProvider {

    @Override
    public InetAddressResolver get(Configuration configuration) {
        return new Guarded(configuration.builtinResolver());
    }

    @Override
    public String name() {
        return "hiwiski-outbound";
    }

    /** The system's resolver, with the check for guarded names. */
    static final class Guarded implements InetAddressResolver {

        private final InetAddressResolver system;

        Guarded(InetAddressResolver system) {
            this.system = system;
        }

        @Override
        public Stream<InetAddress> lookupByName(String host, LookupPolicy policy) throws UnknownHostException {
            List<InetAddress> addresses = system.lookupByName(host, policy).toList();
            if (OutboundUrls.guarded(host) && addresses.stream().anyMatch(OutboundUrls::isPrivate)) {
                throw new UnknownHostException(host + " resolves to an address the server may not fetch from");
            }
            return addresses.stream();
        }

        @Override
        public String lookupByAddress(byte[] address) throws UnknownHostException {
            return system.lookupByAddress(address);
        }
    }
}
