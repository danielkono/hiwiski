package de.danielkononov.hiwiski.platform;

/**
 * The server does not start, for a reason its operator can fix -- said in one English
 * line, with what to do, instead of a stack of bean creation errors.
 */
public class StartRefused extends RuntimeException {

    @java.io.Serial private static final long serialVersionUID = 1L;

    private final String action;

    public StartRefused(String description, String action, Throwable cause) {
        super(description, cause);
        this.action = action;
    }

    public String action() {
        return action;
    }
}
