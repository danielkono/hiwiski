package de.danielkononov.hiwiski.admin.internal;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.AppenderBase;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/**
 * The most recent log lines, in memory.
 *
 * <p>"On the client, logging is local, not sent. The log can be viewed and exported in
 * the account — the user sends it deliberately themselves." The same
 * holds on the server: there is no service anything would go to, so the administrator
 * has to be able to fetch it.
 *
 * <p>In memory and not in a file: the log goes to {@code stdout} anyway and thus into the
 * container's journal. This buffer is just the convenient way to the last lines when
 * someone says "error 8f3c".
 */
public class LogBuffer extends AppenderBase<ILoggingEvent> {

    private static final int CAPACITY = 2000;

    private static final Deque<String> LINES = new ArrayDeque<>(CAPACITY);

    @Override
    protected void append(ILoggingEvent event) {
        String line = "%s %-5s [%s] %s - %s".formatted(
                Instant.ofEpochMilli(event.getTimeStamp()),
                event.getLevel(),
                event.getMDCPropertyMap().getOrDefault("correlationId", "........"),
                event.getLoggerName(),
                event.getFormattedMessage());
        synchronized (LINES) {
            if (LINES.size() == CAPACITY) {
                LINES.removeFirst();
            }
            LINES.addLast(line);
        }
    }

    /** The last {@code limit} lines, oldest first. */
    static List<String> tail(int limit) {
        synchronized (LINES) {
            List<String> all = new ArrayList<>(LINES);
            int from = Math.max(0, all.size() - Math.max(1, limit));
            return List.copyOf(all.subList(from, all.size()));
        }
    }
}
