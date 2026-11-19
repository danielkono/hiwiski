package de.danielkononov.hiwiski.calendar.internal;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.time.DateTimeException;
import java.time.ZoneId;
import java.util.Optional;
import java.util.Properties;
import java.util.regex.Pattern;

/**
 * The IANA zone behind a foreign file's TZID.
 *
 * <p>Not every file names its zones the IANA way: Outlook and Exchange write Windows
 * names ({@code W. Europe Standard Time}), Thunderbird a path ({@code
 * /mozilla.org/20050126_1/Europe/Berlin}). {@code ZoneId.of} threw for both, and every
 * series in such a feed was skipped. Only an IANA ID is stored, because the app and
 * {@code LibRecurRecurrence} expand the series in it.
 */
final class TimeZoneIds {

    private static final Properties WINDOWS = load();

    /** The last {@code Region/City} (or {@code Region/Sub/City}) of a path-like TZID. */
    private static final Pattern REGION = Pattern.compile("([A-Za-z_]+/[A-Za-z_+\\-]+(?:/[A-Za-z_+\\-]+)?)$");

    private TimeZoneIds() {}

    static Optional<ZoneId> resolve(String tzid) {
        if (tzid == null || tzid.isBlank()) {
            return Optional.empty();
        }
        String id = tzid.trim();
        Optional<ZoneId> direct = iana(id);
        if (direct.isPresent()) {
            return direct;
        }
        String windows = WINDOWS.getProperty(id);
        if (windows != null) {
            return iana(windows);
        }
        var region = REGION.matcher(id);
        return region.find() ? iana(region.group(1)) : Optional.empty();
    }

    /**
     * Whether [id] is an IANA ID -- not a zone a parser made up: ical4j registers zones
     * of its own ({@code ical4j-local-406}) as available ones.
     */
    private static boolean isIana(String id) {
        return !id.startsWith("ical4j") && ZoneId.getAvailableZoneIds().contains(id);
    }

    private static Optional<ZoneId> iana(String id) {
        if (!isIana(id)) {
            return Optional.empty();
        }
        try {
            return Optional.of(ZoneId.of(id));
        } catch (DateTimeException e) {
            return Optional.empty();
        }
    }

    private static Properties load() {
        var properties = new Properties();
        try (InputStream in = TimeZoneIds.class.getResourceAsStream("windows-zones.properties")) {
            if (in != null) {
                properties.load(in);
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return properties;
    }
}
