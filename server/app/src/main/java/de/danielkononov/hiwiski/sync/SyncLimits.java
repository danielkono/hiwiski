package de.danielkononov.hiwiski.sync;

import de.danielkononov.hiwiski.platform.HiwiskiException;

/**
 * How large a push may be.
 *
 * <p>Every mutation holds the change sequence's lock, which all writers of the instance
 * take in turn. Without limits one member -- or one stolen device token -- could post a
 * push of a hundred thousand mutations, or megabytes of text in every field, and stall
 * everyone else's sync for as long as it takes. The limits sit far above what a family
 * writes: the app sends 50 mutations at a time, and a long wiki page is a few dozen
 * kilobytes.
 */
public final class SyncLimits {

    /** Mutations per push. The app sends at most 50. */
    public static final int MUTATIONS_PER_PUSH = 200;

    /** Characters in one text field -- a wiki page's content included (about 100 pages). */
    public static final int TEXT_CHARS = 200_000;

    /** Entries in one list of ids: assignees, tags, the calendars of a feed. */
    public static final int IDS = 500;

    /** Characters of one JSON field as stored: a board's columns, a widget's settings. */
    public static final int JSON_CHARS = 256 * 1024;

    /**
     * Keys a merged map (an event's exceptions) may hold in all -- after merging, since it
     * only ever grows.
     */
    public static final int MERGED_KEYS = 5_000;

    /** The code of a value beyond these limits. */
    public static final String VALUE_TOO_LARGE = "sync.value_too_large";

    private SyncLimits() {}

    /** Refuses a value beyond its limit -- as a rejection of the mutation, not a 500. */
    public static void check(boolean within, String field) {
        if (!within) {
            throw HiwiskiException.invalid(VALUE_TOO_LARGE, "field", field);
        }
    }
}
