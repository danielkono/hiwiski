package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.net.spi.InetAddressResolver;
import java.net.spi.InetAddressResolverProvider;
import java.util.ServiceLoader;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * DNS rebinding: a name that resolved to a public address for the check and to the
 * router for the connection. Every lookup of a fetched name is checked.
 */
class OutboundResolverTest {

    /** A DNS server that answers whatever the test says, as a rebinding one does. */
    private static final class Answering implements InetAddressResolver {
        InetAddress answer;

        @Override
        public Stream<InetAddress> lookupByName(String host, LookupPolicy policy) {
            return Stream.of(answer);
        }

        @Override
        public String lookupByAddress(byte[] address) {
            return "x";
        }
    }

    @Test
    void aFetchedNameNeverResolvesToAPrivateAddressAgain() throws Exception {
        var dns = new Answering();
        var resolver = new OutboundResolverProvider.Guarded(dns);
        var policy = InetAddressResolver.LookupPolicy.of(InetAddressResolver.LookupPolicy.IPV4);
        String host = "rebinding.hiwiski.test";

        // Not fetched yet: resolved as the system does.
        dns.answer = InetAddress.getByAddress(new byte[] {(byte) 192, (byte) 168, 1, 1});
        assertThat(resolver.lookupByName(host, policy)).hasSize(1);

        // Fetched: the check passed on a public answer.
        dns.answer = InetAddress.getByAddress(new byte[] {93, (byte) 184, (byte) 216, 34});
        markChecked(host);
        assertThat(resolver.lookupByName(host, policy)).hasSize(1);

        // Then the DNS changes its answer.
        dns.answer = InetAddress.getByAddress(new byte[] {127, 0, 0, 1});
        assertThatThrownBy(() -> resolver.lookupByName(host, policy)).isInstanceOf(UnknownHostException.class);
    }

    /** A name that is private from the start is refused and not guarded. */
    @Test
    void aRefusedNameIsNotGuarded() {
        assertThatThrownBy(() -> OutboundUrls.requirePublic("localhost")).isInstanceOf(HiwiskiException.class);
        assertThat(OutboundUrls.guarded("localhost")).isFalse();
    }

    @Test
    void theJvmUsesIt() {
        assertThat(ServiceLoader.load(InetAddressResolverProvider.class).stream())
                .anyMatch(provider -> provider.type() == OutboundResolverProvider.class);
    }

    /** What `requirePublic` does once the name passed, without a real DNS lookup. */
    private static void markChecked(String host) throws Exception {
        var field = OutboundUrls.class.getDeclaredField("GUARDED");
        field.setAccessible(true);
        @SuppressWarnings("unchecked")
        var guarded = (java.util.Set<String>) field.get(null);
        guarded.add(host);
    }
}
