package de.danielkononov.hiwiski.sync;

import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * A short-lived ticket for the event stream.
 *
 * <p>An SSE stream cannot be opened with a header: {@code EventSource} in the browser
 * cannot send one. The app therefore requests a ticket beforehand and
 * appends it as a query parameter.
 *
 * <p>Public because the <strong>dashboard at its own address</strong> needs one too —
 * and {@code dashboard} must not reach into {@code sync.internal}.
 */
public interface StreamTickets {

    /** @param memberId on whose behalf the stream runs — for a device-less reader */
    default Ticket issue(UUID memberId) {
        return issue(memberId, null);
    }

    /**
     * @param memberId on whose behalf the stream runs
     * @param deviceId the device it runs on; its stream ends when the device is signed out
     */
    Ticket issue(UUID memberId, UUID deviceId);

    /**
     * A ticket for a reader that holds an address instead of a device — the dashboard on
     * the wall tablet. Its stream lasts only as long as the address does.
     *
     * @param memberId on whose behalf the stream runs
     * @param address what the reader opened it with — the board's token
     */
    Ticket issueForAddress(UUID memberId, String address);

    /**
     * The address opens nothing any more — regenerated, or its board is gone. Its streams
     * hear {@code revoked} and end, and a ticket fetched with it but not redeemed yet is
     * void. Before, a stream opened with the old address kept hearing of every change
     * after "Regenerate address".
     */
    void endAddress(String address);

    record Ticket(String value, OffsetDateTime expiresAt) {}
}
