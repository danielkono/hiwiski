package de.danielkononov.hiwiski.platform;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * "No outbound request into the local network."
 *
 * <p>Without this barrier the import becomes a tool for talking to the router. Not an
 * integration test: the check needs no database, and a security test that boots a
 * container eventually gets skipped.
 */
class OutboundUrlsTest {

    @Test
    void publicAddressesPass() {
        // An address, not a name: the test must not need a DNS server -- offline or in a
        // sandboxed build it failed although nothing was wrong.
        assertThat(OutboundUrls.require("https://93.184.216.34/kalender.ics").getHost())
                .isEqualTo("93.184.216.34");
    }

    @Test
    void loopbackIsRejected() {
        assertThatThrownBy(() -> OutboundUrls.require("http://127.0.0.1:8080/x.ics"))
                .isInstanceOf(HiwiskiException.class)
                .hasMessageContaining("net.address_not_allowed");
        assertThatThrownBy(() -> OutboundUrls.require("http://localhost/x.ics"))
                .isInstanceOf(HiwiskiException.class);
    }

    @Test
    void privateNetworkIsRejected() {
        for (String url : new String[] {
            "http://192.168.1.1/x.ics", "http://10.0.0.5/x.ics", "http://172.16.0.1/x.ics"
        }) {
            assertThatThrownBy(() -> OutboundUrls.require(url))
                    .describedAs(url)
                    .isInstanceOf(HiwiskiException.class);
        }
    }

    @Test
    void metadataAddressIsCertainlyRejected() {
        // On every cloud provider, 169.254.169.254 is the way to the machine's
        // credentials.
        assertThatThrownBy(() -> OutboundUrls.require("http://169.254.169.254/latest/meta-data/"))
                .isInstanceOf(HiwiskiException.class)
                .hasMessageContaining("net.address_not_allowed");
    }

    @Test
    void onlyHttpAndHttps() {
        for (String url : new String[] {"file:///etc/passwd", "gopher://example.com/", "ftp://example.com/x"}) {
            assertThatThrownBy(() -> OutboundUrls.require(url))
                    .describedAs(url)
                    .isInstanceOf(HiwiskiException.class);
        }
    }
}
