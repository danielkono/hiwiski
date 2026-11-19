package de.danielkononov.hiwiski.identity;

/**
 * The setup wizard's gate, for a module that offers a step of its own in it: restoring
 * an archive on a fresh server.
 *
 * <p>The same two barriers as the wizard itself: the setup code from the server's log,
 * and an instance that nobody has set up yet.
 */
public interface SetupGate {

    /** Whether the wizard has run -- or an archive was restored in its place. */
    boolean completed();

    /**
     * Refuses a missing or wrong setup code with {@code 403 setup.code_invalid}, and too
     * many wrong ones from one address with {@code 429}.
     */
    void requireCode(String code, String client);

    /**
     * Refuses an instance set up already with {@code 409 setup.already_completed}: the
     * flag says the wizard has run, the member count that someone already exists.
     */
    void requireFresh();

    /**
     * {@link #requireFresh()}, held until the caller's transaction ends: the wizard and
     * a restore on a fresh server each check "nobody yet" first and write later, and two
     * at once both passed -- the later one replaced the earlier one's family. Whoever
     * comes second waits here and is then refused.
     */
    void requireFreshAndHold();

    /** The address of the client of the current request, as the sign-in budget sees it. */
    String currentClient();
}
