package de.danielkononov.hiwiski.identity.internal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

/**
 * Passwords with Argon2id.
 *
 * <p>The parameters are the ones Spring Security recommends for Argon2id: 16-byte salt,
 * 32-byte hash, one thread, 64 MiB of memory, three iterations. The memory cost is the
 * point -- it makes brute-forcing on a GPU expensive, and a home server computes this a
 * few times a day. It is also why only a few run at once ({@link BoundedPasswordEncoder}).
 */
@Configuration
class PasswordEncoderConfig {

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BoundedPasswordEncoder(
                new Argon2PasswordEncoder(16, 32, 1, 1 << 16, 3),
                BoundedPasswordEncoder.concurrentFor(Runtime.getRuntime().maxMemory()));
    }
}
