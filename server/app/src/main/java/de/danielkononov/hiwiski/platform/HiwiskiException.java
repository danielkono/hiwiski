package de.danielkononov.hiwiski.platform;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;

/**
 * A domain error as it goes to the client: <strong>code plus parameters, never a
 * finished German sentence</strong>.
 *
 * <p>The client translates via ARB. An unknown code is shown as the code -- that is ugly
 * and honest, and better than an empty dialog.
 *
 * <p>The exception's message is <em>English</em> and meant for the server log, not for
 * the user.
 */
public class HiwiskiException extends RuntimeException {

    // This exception is never serialized -- it lives between service and advice.
    @java.io.Serial private static final long serialVersionUID = 1L;

    @SuppressWarnings("serial")
    private final String code;
    @SuppressWarnings("serial")
    private final Map<String, String> params;
    @SuppressWarnings("serial")
    private final HttpStatus status;

    /**
     * A parameter that also goes out as the {@code Retry-After} header: how many
     * seconds until the request may be tried again.
     */
    public static final String RETRY_AFTER_SECONDS = "retryAfterSeconds";

    public HiwiskiException(HttpStatus status, String code, Map<String, String> params) {
        super(status.value() + " " + code + " " + params);
        this.status = status;
        this.code = code;
        this.params = Map.copyOf(params);
    }

    public String code() {
        return code;
    }

    public Map<String, String> params() {
        return params;
    }

    public HttpStatus status() {
        return status;
    }

    // --- The standard cases of the error model, so that the code -> status mapping is not
    // --- reinvented at every call site.

    /** 400 -- invalid in the domain. */
    public static HiwiskiException invalid(String code, Object... keyValuePairs) {
        return new HiwiskiException(HttpStatus.BAD_REQUEST, code, params(keyValuePairs));
    }

    /** 403 -- not shared. Only where the existence is known anyway. */
    public static HiwiskiException forbidden(String code, Object... keyValuePairs) {
        return new HiwiskiException(HttpStatus.FORBIDDEN, code, params(keyValuePairs));
    }

    /**
     * 404 -- does not exist <em>or</em> is not visible.
     *
     * <p>The same answer for both: a {@code 403} would reveal the existence, and the
     * existence is information too.
     */
    public static HiwiskiException notFound(String code, Object... keyValuePairs) {
        return new HiwiskiException(HttpStatus.NOT_FOUND, code, params(keyValuePairs));
    }

    /** 409 -- conflict. */
    public static HiwiskiException conflict(String code, Object... keyValuePairs) {
        return new HiwiskiException(HttpStatus.CONFLICT, code, params(keyValuePairs));
    }

    private static Map<String, String> params(Object... keyValuePairs) {
        if (keyValuePairs.length % 2 != 0) {
            throw new IllegalArgumentException("params need an even number of arguments");
        }
        Map<String, String> result = new LinkedHashMap<>();
        for (int i = 0; i < keyValuePairs.length; i += 2) {
            result.put(String.valueOf(keyValuePairs[i]), String.valueOf(keyValuePairs[i + 1]));
        }
        return result;
    }
}
