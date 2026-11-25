package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_NODE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.sync.Archive;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * A mind map's elements and connections, each an item of its own in its page.
 *
 * <p>Items of their own, not a property of the page: a property is one field, replaced
 * as a whole, and two people moving different elements of the same map would collide
 * over all of it. As items, each field of each element has its own conflict check --
 * moving one element while someone recolours it goes through for both, and a conflict
 * names the one element both changed. The same reason made a checked-off occurrence of
 * a task an item of its own.
 *
 * <p>Both inherit their page's share: whoever may write the page may change the map.
 */
@Configuration
class MindmapSyncTypes {

    static final String NODE_TYPE = "MINDMAP_NODE";
    static final String EDGE_TYPE = "MINDMAP_EDGE";

    /** An element or a connection on a page that is no mind map, or none that lives. */
    static final String NOT_A_MINDMAP = "wiki.not_a_mindmap";

    /** A connection whose element is gone, on another page, or the same at both ends. */
    static final String ELEMENT_GONE = "wiki.mindmap_element_gone";

    private static final String COLOR = "color";
    private static final String TEXT_COLOR = "textColor";
    private static final String POINTS = "points";
    private static final String TEXT_SIZE = "textSize";
    private static final String STROKE_WIDTH = "strokeWidth";
    private static final String ROTATION = "rotation";
    private static final String TEXT_ALIGN = "textAlign";
    private static final String TEXT_FLOW = "textFlow";
    private static final String CALENDARS = "calendars";
    private static final String WEEK = "week";
    private static final String TARGET = "target";
    private static final String LINK_VIEW = "linkView";
    private static final String WIDTH = "width";
    private static final String HEIGHT = "height";
    private static final String FROM_ID = "fromId";
    private static final String TO_ID = "toId";
    private static final String LINE = "line";
    private static final String ARROWS = "arrows";

    /**
     * A colour is an accent token the app maps to the light and the dark theme, or the
     * family's own as {@code #RRGGBB}, which the app adapts to the theme. A token is any
     * name in capitals, not just today's: the list of tokens may grow, and an older app
     * falls back on one it does not know.
     */
    private static final Pattern COLOR_VALUE = Pattern.compile("[A-Z][A-Z_]{0,31}|#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?");

    /**
     * How a link element shows its target -- {@code TITLE} or {@code CONTENT}. Any name
     * in capitals: an older app shows a way it does not know as the title.
     */
    private static final Pattern LINK_VIEW_VALUE = Pattern.compile("[A-Z][A-Z_]{0,31}");

    /**
     * How a connection is drawn — its line, its arrow heads — named in capitals as well:
     * an app draws a way it does not know as a plain line without heads.
     */
    private static final Pattern EDGE_STYLE_VALUE = Pattern.compile("[A-Z][A-Z_]{0,31}");

    /**
     * A link element points to an item in the app, never to an address outside it -- and
     * a member element to a member: a type and an id the app can read as one.
     */
    private static final Pattern TARGET_VALUE = Pattern.compile(
            "hiwiski://[a-z_]+/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

    /**
     * The calendars a week of calendars shows: their ids, separated by spaces. Which of
     * them a reader sees is decided where it is shown, as on the calendar's own page.
     */
    private static final Pattern CALENDARS_VALUE = Pattern.compile(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
                    + "( [0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}){0,49}");

    /** A week of the year as ISO 8601 writes it, Monday to Sunday: {@code 2027-W28}. */
    private static final Pattern WEEK_VALUE = Pattern.compile("[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])");

    /** Far beyond any element a person draws; it keeps a typo from making one endless. */
    private static final int MAX_SIZE = 100_000;

    /** A stroke of some thousand points; the app thins out what is drawn longer. */
    private static final int MAX_POINTS_CHARS = 100_000;

    /**
     * A stroke's points lie across its element, from 0 to this on either axis: the app
     * draws a point beyond it outside the element, where nothing else of it is.
     */
    private static final int STROKE_SCALE = 10_000;

    /** Thicker than any pen; a stroke is at least a line. */
    private static final int MAX_STROKE_WIDTH = 1_000;
    private static final int FULL_TURN = 360;

    private final DSLContext db;

    MindmapSyncTypes(DSLContext db) {
        this.db = db;
    }

    @Bean
    SyncType mindmapNodeSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return NODE_TYPE;
            }

            @Override
            public Table<?> table() {
                return MINDMAP_NODE;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("kind", MINDMAP_NODE.KIND),
                        // Position and size are a field each: one person dragging an
                        // element while another makes it wider both get through.
                        SyncField.integer("x", MINDMAP_NODE.X),
                        SyncField.integer("y", MINDMAP_NODE.Y),
                        SyncField.integer(WIDTH, MINDMAP_NODE.WIDTH),
                        SyncField.integer(HEIGHT, MINDMAP_NODE.HEIGHT),
                        SyncField.decimal("layer", MINDMAP_NODE.LAYER),
                        // A picture element's pictures are Markdown images in its text,
                        // as in a page's: one way to keep, show and clean them up.
                        SyncField.text("text", MINDMAP_NODE.TEXT),
                        SyncField.text(TARGET, MINDMAP_NODE.TARGET),
                        SyncField.text(LINK_VIEW, MINDMAP_NODE.LINK_VIEW),
                        SyncField.text(COLOR, MINDMAP_NODE.COLOR),
                        SyncField.text("shape", MINDMAP_NODE.SHAPE),
                        SyncField.text(TEXT_SIZE, MINDMAP_NODE.TEXT_SIZE),
                        SyncField.text(TEXT_COLOR, MINDMAP_NODE.TEXT_COLOR),
                        // A stroke drawn by hand: one field, as it is drawn and erased
                        // as one.
                        SyncField.text(POINTS, MINDMAP_NODE.POINTS),
                        SyncField.integer(STROKE_WIDTH, MINDMAP_NODE.STROKE_WIDTH),
                        SyncField.integer(ROTATION, MINDMAP_NODE.ROTATION),
                        SyncField.text(TEXT_ALIGN, MINDMAP_NODE.TEXT_ALIGN),
                        SyncField.text(TEXT_FLOW, MINDMAP_NODE.TEXT_FLOW),
                        SyncField.text(CALENDARS, MINDMAP_NODE.CALENDARS),
                        SyncField.text(WEEK, MINDMAP_NODE.WEEK));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(WikiSyncTypes.PAGE_TYPE, MINDMAP_NODE.PAGE_ID));
            }

            @Override
            public Optional<String> refusal(UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                Map<String, Object> changes = fields == null ? Map.of() : fields;
                Optional<String> page = pageRefusal(containerId);
                if (page.isPresent()) {
                    return page;
                }
                if (!fitsColor(changes)
                        || !fitsSize(changes)
                        || !fitsTarget(changes)
                        || !fitsLinkView(changes)
                        || !fitsStroke(changes)
                        || !fitsTextSize(changes)
                        || !fitsRotation(changes)
                        || !fitsTextPlace(changes)
                        || !fitsWeekOfCalendars(changes)) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                return Optional.empty();
            }

            /** With an element go the connections at either end of it. */
            @Override
            public List<Ref> alsoDeleted(UUID entityId) {
                return db.select(MINDMAP_EDGE.ID)
                        .from(MINDMAP_EDGE)
                        .where(MINDMAP_EDGE.FROM_ID.eq(entityId).or(MINDMAP_EDGE.TO_ID.eq(entityId)))
                        .and(MINDMAP_EDGE.DELETED_AT.isNull())
                        .fetch(MINDMAP_EDGE.ID)
                        .stream()
                        .map(id -> new Ref(EDGE_TYPE, id))
                        .toList();
            }

            /**
             * Its connections come back with it -- those that went along and whose other
             * end lives: a connection to an element that is still gone would point at
             * nothing.
             */
            @Override
            public List<Ref> alsoRestored(UUID entityId, OffsetDateTime deletedAt) {
                var from = MINDMAP_NODE.as("from_node");
                var to = MINDMAP_NODE.as("to_node");
                return db.select(MINDMAP_EDGE.ID)
                        .from(MINDMAP_EDGE)
                        .join(from).on(from.ID.eq(MINDMAP_EDGE.FROM_ID))
                        .join(to).on(to.ID.eq(MINDMAP_EDGE.TO_ID))
                        .where(MINDMAP_EDGE.FROM_ID.eq(entityId).or(MINDMAP_EDGE.TO_ID.eq(entityId)))
                        .and(MINDMAP_EDGE.DELETED_AT.ge(deletedAt))
                        .and(from.DELETED_AT.isNull())
                        .and(to.DELETED_AT.isNull())
                        .fetch(MINDMAP_EDGE.ID)
                        .stream()
                        .map(id -> new Ref(EDGE_TYPE, id))
                        .toList();
            }
        };
    }

    @Bean
    SyncType mindmapEdgeSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return EDGE_TYPE;
            }

            @Override
            public Table<?> table() {
                return MINDMAP_EDGE;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.uuid(FROM_ID, MINDMAP_EDGE.FROM_ID),
                        SyncField.uuid(TO_ID, MINDMAP_EDGE.TO_ID),
                        SyncField.text("text", MINDMAP_EDGE.TEXT),
                        SyncField.text(COLOR, MINDMAP_EDGE.COLOR),
                        SyncField.integer(STROKE_WIDTH, MINDMAP_EDGE.STROKE_WIDTH),
                        SyncField.text(LINE, MINDMAP_EDGE.LINE),
                        SyncField.text(ARROWS, MINDMAP_EDGE.ARROWS));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(WikiSyncTypes.PAGE_TYPE, MINDMAP_EDGE.PAGE_ID));
            }

            /**
             * A connection joins two living elements of its own page, and keeps them.
             *
             * <p>Checked on every write, not only the first: an edit that arrives for a
             * connection taken along with its element brings it back, and it must not
             * come back pointing at nothing. Moved to other ends, it would be another
             * connection under the same id -- the app deletes and draws a new one.
             */
            @Override
            public Optional<String> refusal(UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                Map<String, Object> changes = fields == null ? Map.of() : fields;
                Optional<String> page = pageRefusal(containerId);
                if (page.isPresent()) {
                    return page;
                }
                if (!fitsColor(changes) || !fitsStroke(changes) || !fitsEdgeStyle(changes)) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                var stored = exists
                        ? db.select(MINDMAP_EDGE.FROM_ID, MINDMAP_EDGE.TO_ID)
                                .from(MINDMAP_EDGE)
                                .where(MINDMAP_EDGE.ID.eq(entityId))
                                .fetchOne()
                        : null;
                if (stored != null
                        && (changed(changes, FROM_ID, stored.value1()) || changed(changes, TO_ID, stored.value2()))) {
                    return Optional.of(SyncField.INVALID_FIELD);
                }
                UUID from = stored != null ? stored.value1() : id(changes.get(FROM_ID));
                UUID to = stored != null ? stored.value2() : id(changes.get(TO_ID));
                if (from == null || to == null || from.equals(to) || !livesOn(from, containerId) || !livesOn(to, containerId)) {
                    return Optional.of(ELEMENT_GONE);
                }
                return Optional.empty();
            }
        };
    }

    /** Why nothing may be written on this page's map -- or empty. */
    private Optional<String> pageRefusal(UUID pageId) {
        if (pageId == null) {
            return Optional.of(NOT_A_MINDMAP);
        }
        var page = db.select(WIKI_PAGE.KIND, WIKI_PAGE.ARCHIVED_AT)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .and(WIKI_PAGE.DELETED_AT.isNull())
                .fetchOne();
        if (page == null || !MindmapKind.CODE.equals(page.value1())) {
            return Optional.of(NOT_A_MINDMAP);
        }
        // An archived page is read-only, and its map with it.
        if (page.value2() != null) {
            return Optional.of(Archive.READ_ONLY);
        }
        return Optional.empty();
    }

    private static boolean fitsColor(Map<String, Object> changes) {
        return Stream.of(COLOR, TEXT_COLOR).map(changes::get)
                .allMatch(color -> color == null || COLOR_VALUE.matcher(color.toString()).matches());
    }

    private static boolean fitsLinkView(Map<String, Object> changes) {
        Object view = changes.get(LINK_VIEW);
        return view == null || LINK_VIEW_VALUE.matcher(view.toString()).matches();
    }

    /** A whole turn is none: one way of writing each angle, so two devices agree. */
    private static boolean fitsRotation(Map<String, Object> changes) {
        Object rotation = changes.get(ROTATION);
        return rotation == null
                || (rotation instanceof Number number
                        && number.doubleValue() == number.longValue()
                        && number.longValue() >= 0
                        && number.longValue() < FULL_TURN);
    }

    /**
     * A place for the text and what its lines fill, named in capitals as a connection's
     * line is.
     */
    private static boolean fitsTextPlace(Map<String, Object> changes) {
        return Stream.of(TEXT_ALIGN, TEXT_FLOW).map(changes::get)
                .allMatch(name -> name == null || EDGE_STYLE_VALUE.matcher(name.toString()).matches());
    }

    private static boolean fitsWeekOfCalendars(Map<String, Object> changes) {
        Object calendars = changes.get(CALENDARS);
        Object week = changes.get(WEEK);
        return (calendars == null || CALENDARS_VALUE.matcher(calendars.toString()).matches())
                && (week == null || WEEK_VALUE.matcher(week.toString()).matches());
    }

    private static boolean fitsEdgeStyle(Map<String, Object> changes) {
        return Stream.of(LINE, ARROWS).map(changes::get)
                .allMatch(style -> style == null || EDGE_STYLE_VALUE.matcher(style.toString()).matches());
    }

    private static boolean fitsTarget(Map<String, Object> changes) {
        Object target = changes.get(TARGET);
        return target == null || TARGET_VALUE.matcher(target.toString()).matches();
    }

    private static boolean fitsStroke(Map<String, Object> changes) {
        Object points = changes.get(POINTS);
        Object width = changes.get(STROKE_WIDTH);
        boolean pointsFit = points == null || isPoints(points.toString());
        boolean widthFits = width == null
                || (width instanceof Number number && number.longValue() >= 1 && number.longValue() <= MAX_STROKE_WIDTH);
        return pointsFit && widthFits;
    }

    /**
     * A stroke's points, each as two whole numbers across its element:
     * {@code x,y x,y ...}. Read by hand, not by a pattern: a repeated group over a
     * hundred thousand characters runs a regular expression out of stack.
     */
    private static boolean isPoints(String value) {
        if (value.isEmpty() || value.length() > MAX_POINTS_CHARS) {
            return false;
        }
        for (String point : value.split(" ", -1)) {
            int comma = point.indexOf(',');
            if (comma < 0 || !isAcross(point.substring(0, comma)) || !isAcross(point.substring(comma + 1))) {
                return false;
            }
        }
        return true;
    }

    private static boolean isAcross(String coordinate) {
        return isWhole(coordinate) && Integer.parseInt(coordinate) <= STROKE_SCALE;
    }

    /**
     * A text size: a name in capitals ({@code S} … {@code XL}; an older app shows one it
     * does not know as medium), or a size of its own in logical pixels.
     */
    private static boolean fitsTextSize(Map<String, Object> changes) {
        Object size = changes.get(TEXT_SIZE);
        if (size == null) {
            return true;
        }
        String value = size.toString();
        if (value.chars().allMatch(c -> c >= 'A' && c <= 'Z') && !value.isEmpty() && value.length() <= 4) {
            return true;
        }
        if (!isWhole(value)) {
            return false;
        }
        int pixels = Integer.parseInt(value);
        return pixels >= MIN_TEXT_SIZE && pixels <= MAX_TEXT_SIZE;
    }

    /** From what is still read up close to a heading across a wall. */
    private static final int MIN_TEXT_SIZE = 4;

    private static final int MAX_TEXT_SIZE = 400;

    /**
     * Digits 0 to 9 only: {@link Character#isDigit} takes the digits of every script,
     * which the app does not read as a number.
     */
    private static boolean isWhole(String part) {
        return !part.isEmpty() && part.length() <= 5 && part.chars().allMatch(c -> c >= '0' && c <= '9');
    }

    private static boolean fitsSize(Map<String, Object> changes) {
        return Stream.of(WIDTH, HEIGHT).map(changes::get).allMatch(value -> value == null
                || (value instanceof Number number && number.longValue() >= 1 && number.longValue() <= MAX_SIZE));
    }

    private boolean livesOn(UUID node, UUID pageId) {
        return db.fetchExists(db.selectOne()
                .from(MINDMAP_NODE)
                .where(MINDMAP_NODE.ID.eq(node))
                .and(MINDMAP_NODE.PAGE_ID.eq(pageId))
                .and(MINDMAP_NODE.DELETED_AT.isNull()));
    }

    private static boolean changed(Map<String, Object> changes, String field, UUID stored) {
        return changes.containsKey(field) && !stored.equals(id(changes.get(field)));
    }

    private static UUID id(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return UUID.fromString(value.toString());
        } catch (IllegalArgumentException notAnId) {
            return null;
        }
    }

    /**
     * Every element and connection of a page that went with it -- deleted at or after
     * the page. The elements first: their connections need both ends alive.
     */
    List<SyncType.Ref> deletedWith(UUID pageId, OffsetDateTime deletedAt) {
        var nodes = db.select(MINDMAP_NODE.ID)
                .from(MINDMAP_NODE)
                .where(MINDMAP_NODE.PAGE_ID.eq(pageId))
                .and(MINDMAP_NODE.DELETED_AT.ge(deletedAt))
                .fetch(MINDMAP_NODE.ID)
                .stream()
                .map(id -> new SyncType.Ref(NODE_TYPE, id));
        var edges = db.select(MINDMAP_EDGE.ID)
                .from(MINDMAP_EDGE)
                .where(MINDMAP_EDGE.PAGE_ID.eq(pageId))
                .and(MINDMAP_EDGE.DELETED_AT.ge(deletedAt))
                .fetch(MINDMAP_EDGE.ID)
                .stream()
                .map(id -> new SyncType.Ref(EDGE_TYPE, id));
        return Stream.concat(nodes, edges).toList();
    }

    /** Every living element and connection of a page -- what goes along with it. */
    List<SyncType.Ref> livingOn(UUID pageId) {
        var nodes = db.select(MINDMAP_NODE.ID)
                .from(MINDMAP_NODE)
                .where(MINDMAP_NODE.PAGE_ID.eq(pageId))
                .and(MINDMAP_NODE.DELETED_AT.isNull())
                .fetch(MINDMAP_NODE.ID)
                .stream()
                .map(id -> new SyncType.Ref(NODE_TYPE, id));
        var edges = db.select(MINDMAP_EDGE.ID)
                .from(MINDMAP_EDGE)
                .where(MINDMAP_EDGE.PAGE_ID.eq(pageId))
                .and(MINDMAP_EDGE.DELETED_AT.isNull())
                .fetch(MINDMAP_EDGE.ID)
                .stream()
                .map(id -> new SyncType.Ref(EDGE_TYPE, id));
        // Connections first: deleting an element takes its connections along anyway,
        // and listed after it they would be deleted a second time.
        return Stream.concat(edges, nodes).toList();
    }
}
