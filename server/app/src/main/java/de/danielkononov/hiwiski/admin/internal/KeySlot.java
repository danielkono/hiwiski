package de.danielkononov.hiwiski.admin.internal;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Optional;
import javax.crypto.AEADBadTagException;
import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.bouncycastle.crypto.generators.Argon2BytesGenerator;
import org.bouncycastle.crypto.params.Argon2Parameters;

/**
 * The backup's private key, wrapped with the backup password.
 *
 * <p>Argon2id derives a key from the password -- memory-hard, with the parameters the
 * member passwords use -- and ChaCha20-Poly1305 wraps the age identity with it. Salt and
 * parameters are stored with it, so a slot opens on any server, years later, without
 * anything but the password.
 *
 * <p>A slot is {@value #SIZE} bytes, always: it sits in the database and twice in the
 * fixed-size header of every archive, where a change of password overwrites it in
 * place. The checksum at its end tells a slot written whole from one cut off by a power
 * cut; the counter tells the newer of two whole ones.
 *
 * @param counter grows with every change of password, so the newer slot wins
 * @param wrapped the age identity ({@code AGE-SECRET-KEY-1…}), encrypted and
 *     authenticated
 */
record KeySlot(long counter, int memoryKiB, int iterations, int parallelism, byte[] salt, byte[] nonce, byte[] wrapped) {

    static final int SIZE = 256;

    /** The member passwords' Argon2id parameters (PasswordEncoderConfig): 64 MiB, three passes. */
    private static final int MEMORY_KIB = 1 << 16;

    private static final int ITERATIONS = 3;
    private static final int PARALLELISM = 1;

    /** The most a slot may ask for: four times what this server writes. */
    static final int MAX_MEMORY_KIB = 1 << 18;

    static final int MAX_ITERATIONS = 12;
    static final int MAX_PARALLELISM = 4;

    private static final int SALT_BYTES = 16;
    private static final int NONCE_BYTES = 12;
    private static final int CHECKSUM_BYTES = 32;
    private static final int MAX_WRAPPED = SIZE - CHECKSUM_BYTES - 51;

    /** Binds the wrapped key to what it is: a key wrapped for anything else does not open here. */
    private static final byte[] CONTEXT = "hiwiski backup key v1".getBytes(StandardCharsets.US_ASCII);

    private static final SecureRandom RANDOM = new SecureRandom();

    /** Wraps {@code identity} with {@code password}, under a fresh salt and nonce. */
    static KeySlot wrap(String identity, String password, long counter) {
        byte[] salt = new byte[SALT_BYTES];
        byte[] nonce = new byte[NONCE_BYTES];
        RANDOM.nextBytes(salt);
        RANDOM.nextBytes(nonce);
        byte[] key = derive(password, salt, MEMORY_KIB, ITERATIONS, PARALLELISM);
        try {
            byte[] wrapped = cipher(Cipher.ENCRYPT_MODE, key, nonce).doFinal(identity.getBytes(StandardCharsets.US_ASCII));
            return new KeySlot(counter, MEMORY_KIB, ITERATIONS, PARALLELISM, salt, nonce, wrapped);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("could not wrap the backup key", e);
        } finally {
            Arrays.fill(key, (byte) 0);
        }
    }

    /** The age identity, or empty if {@code password} is not the one it was wrapped with. */
    Optional<String> unwrap(String password) {
        byte[] key = derive(password, salt, memoryKiB, iterations, parallelism);
        try {
            return Optional.of(new String(cipher(Cipher.DECRYPT_MODE, key, nonce).doFinal(wrapped), StandardCharsets.US_ASCII));
        } catch (AEADBadTagException e) {
            return Optional.empty();
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("could not unwrap the backup key", e);
        } finally {
            Arrays.fill(key, (byte) 0);
        }
    }

    byte[] toBytes() {
        if (wrapped.length > MAX_WRAPPED) {
            throw new IllegalStateException("wrapped backup key too long: " + wrapped.length);
        }
        ByteBuffer buffer = ByteBuffer.allocate(SIZE);
        buffer.put((byte) 1)
                .putLong(counter)
                .putInt(memoryKiB)
                .putInt(iterations)
                .putInt(parallelism)
                .put(salt)
                .put(nonce)
                .putShort((short) wrapped.length)
                .put(wrapped);
        byte[] bytes = buffer.array();
        System.arraycopy(checksum(bytes), 0, bytes, SIZE - CHECKSUM_BYTES, CHECKSUM_BYTES);
        return bytes;
    }

    /** The slot in {@code bytes}, or empty if it is unused or was not written whole. */
    static Optional<KeySlot> fromBytes(byte[] bytes) {
        if (bytes.length != SIZE || bytes[0] != 1) {
            return Optional.empty();
        }
        byte[] stored = Arrays.copyOfRange(bytes, SIZE - CHECKSUM_BYTES, SIZE);
        if (!MessageDigest.isEqual(stored, checksum(bytes))) {
            return Optional.empty();
        }
        ByteBuffer buffer = ByteBuffer.wrap(bytes, 1, SIZE - 1);
        long counter = buffer.getLong();
        int memory = buffer.getInt();
        int iterations = buffer.getInt();
        int parallelism = buffer.getInt();
        byte[] salt = new byte[SALT_BYTES];
        byte[] nonce = new byte[NONCE_BYTES];
        buffer.get(salt).get(nonce);
        int length = Short.toUnsignedInt(buffer.getShort());
        if (length > MAX_WRAPPED) {
            return Optional.empty();
        }
        // The parameters come from the file, and an uploaded one is anybody's: a header
        // naming gigabytes of memory or thousands of passes took the server down at
        // "inspect", before any password was checked.
        if (memory < 8 || memory > MAX_MEMORY_KIB
                || iterations < 1 || iterations > MAX_ITERATIONS
                || parallelism < 1 || parallelism > MAX_PARALLELISM) {
            return Optional.empty();
        }
        byte[] wrapped = new byte[length];
        buffer.get(wrapped);
        return Optional.of(new KeySlot(counter, memory, iterations, parallelism, salt, nonce, wrapped));
    }

    private static byte[] checksum(byte[] slot) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(Arrays.copyOf(slot, SIZE - CHECKSUM_BYTES));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private static byte[] derive(String password, byte[] salt, int memoryKiB, int iterations, int parallelism) {
        Argon2BytesGenerator generator = new Argon2BytesGenerator();
        generator.init(new Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
                .withVersion(Argon2Parameters.ARGON2_VERSION_13)
                .withSalt(salt)
                .withMemoryAsKB(memoryKiB)
                .withIterations(iterations)
                .withParallelism(parallelism)
                .build());
        byte[] key = new byte[32];
        generator.generateBytes(password.getBytes(StandardCharsets.UTF_8), key);
        return key;
    }

    private static Cipher cipher(int mode, byte[] key, byte[] nonce) throws GeneralSecurityException {
        Cipher cipher = Cipher.getInstance("ChaCha20-Poly1305");
        cipher.init(mode, new SecretKeySpec(key, "ChaCha20"), new IvParameterSpec(nonce));
        cipher.updateAAD(CONTEXT);
        return cipher;
    }

    // A record compares arrays by reference; a slot is its bytes.
    @Override
    public String toString() {
        return "KeySlot[counter=" + counter + "]";
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof KeySlot slot && Arrays.equals(toBytes(), slot.toBytes());
    }

    @Override
    public int hashCode() {
        return Arrays.hashCode(toBytes());
    }
}
