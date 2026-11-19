package de.danielkononov.hiwiski.platform.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.regex.Pattern;
import org.apache.catalina.valves.RemoteIpValve;
import org.junit.jupiter.api.Test;
import org.springframework.boot.tomcat.servlet.TomcatServletWebServerFactory;

/** Whose forwarded headers count. */
class TrustedProxiesTest {

    private static boolean trusted(String pattern, String address) {
        return Pattern.compile(pattern).matcher(address).matches();
    }

    @Test
    void withNoProxyOnlyLoopbackIsTrusted() {
        String pattern = TrustedProxies.pattern("");
        assertThat(trusted(pattern, "127.0.0.1")).isTrue();
        assertThat(trusted(pattern, "0:0:0:0:0:0:0:1")).isTrue();
        // A device on the home network reaching the port directly names no address.
        assertThat(trusted(pattern, "192.168.1.20")).isFalse();
        assertThat(trusted(pattern, "10.0.0.5")).isFalse();
        assertThat(trusted(pattern, "172.18.0.3")).isFalse();
        assertThat(trusted(pattern, "fe80:0:0:0:0:0:0:1")).isFalse();
        assertThat(trusted(pattern, "fd00:0:0:0:0:0:0:2")).isFalse();
    }

    @Test
    void theNamedProxyIsTrustedAndNothingNextToIt() {
        String pattern = TrustedProxies.pattern("10.217.84.2, fd0e:217:53::2");
        assertThat(trusted(pattern, "10.217.84.2")).isTrue();
        assertThat(trusted(pattern, "fd0e:217:53:0:0:0:0:2")).isTrue();
        assertThat(trusted(pattern, "fd0e:217:53::2")).isTrue();
        assertThat(trusted(pattern, "127.0.0.1")).isTrue();
        // The other containers on the same network, and look-alikes of the address.
        assertThat(trusted(pattern, "10.217.84.130")).isFalse();
        assertThat(trusted(pattern, "10.217.84.20")).isFalse();
        assertThat(trusted(pattern, "10x217x84x2")).isFalse();
        assertThat(trusted(pattern, "fd0e:217:53:0:0:0:0:8001")).isFalse();
    }

    @Test
    void aNameOrTypoStopsTheStart() {
        assertThatThrownBy(() -> TrustedProxies.pattern("caddy"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("caddy");
        assertThatThrownBy(() -> TrustedProxies.pattern("10.217.84.300"))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void theOperatorsExpressionWinsWhenSet_andAnEmptyOneDoesNot() {
        assertThat(new TrustedProxies("10.217.84.2", "192\\.168\\.1\\.2").pattern()).isEqualTo("192\\.168\\.1\\.2");
        // The compose files pass SERVER_TOMCAT_REMOTEIP_INTERNALPROXIES through empty:
        // that must not turn into Tomcat's "trust nobody".
        assertThat(new TrustedProxies("10.217.84.2", "").pattern()).isEqualTo(TrustedProxies.pattern("10.217.84.2"));
    }

    @Test
    void theValveGetsThePattern() {
        var factory = new TomcatServletWebServerFactory();
        var valve = new RemoteIpValve();
        valve.setInternalProxies("10\\.\\d+\\.\\d+\\.\\d+");
        factory.addEngineValves(valve);

        new TrustedProxies("10.217.84.2", "").customize(factory);

        assertThat(valve.getInternalProxies()).isEqualTo(TrustedProxies.pattern("10.217.84.2"));
    }
}
