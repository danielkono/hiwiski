package de.danielkononov.hiwiski.platform;

/**
 * The correlation ID of the current request.
 *
 * <p>It appears in the server log <em>and</em> in the error sent to the client. A user
 * who says "error 8f3c" can thus be traced.
 */
public final class CorrelationId {

    /** Key in the MDC and name of the response header. */
    public static final String MDC_KEY = "correlationId";

    public static final String HEADER = "X-Correlation-Id";

    private static final ThreadLocal<String> CURRENT = new ThreadLocal<>();

    private CorrelationId() {}

    public static void set(String value) {
        CURRENT.set(value);
    }

    public static String get() {
        return CURRENT.get();
    }

    public static void clear() {
        CURRENT.remove();
    }
}
