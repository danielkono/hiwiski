package de.danielkononov.hiwiski.dashboard.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.BOARD;
import static de.danielkononov.hiwiski.db.generated.Tables.WIDGET;

import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Table;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code dashboard} registers with sync.
 *
 * <p>Boards and widgets go through sync like any other item: they belong to a member,
 * are set up on the phone and should show up on the tablet right away.
 */
@Configuration
class DashboardSyncTypes {

    static final String BOARD_TYPE = "BOARD";
    static final String WIDGET_TYPE = "WIDGET";

    private final DSLContext db;

    /** At least 32 characters an address can carry as they are. */
    private static final java.util.regex.Pattern TOKEN = java.util.regex.Pattern.compile("[A-Za-z0-9_-]{32,128}");

    static final String TOKEN_INVALID = "dashboard.token_invalid";

    /**
     * Whether a token looks drawn at random: long enough is not enough, forty times the
     * same letter passed. A random one of this length has far more than eight different
     * characters, whatever alphabet a device draws from.
     */
    static boolean varied(String token) {
        return token.chars().distinct().count() >= 8;
    }

    static final String LAYOUT_INVALID = "dashboard.layout_invalid";

    /** The layouts the clients know. */
    private static final java.util.Set<Object> LAYOUTS = java.util.Set.of("GRID", "FLOW");

    DashboardSyncTypes(DSLContext db) {
        this.db = db;
    }

    @Bean
    SyncType boardSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return BOARD_TYPE;
            }

            @Override
            public Table<?> table() {
                return BOARD;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("kind", BOARD.KIND),
                        SyncField.text("name", BOARD.NAME),
                        SyncField.text("layout", BOARD.LAYOUT),
                        SyncField.integer("columns", BOARD.COLUMNS),
                        // The token travels along: the address has to be displayable on
                        // every device of the owner -- that is exactly why it is stored
                        // in plain text.
                        SyncField.text("token", BOARD.TOKEN));
            }

            /**
             * The address works without signing in, so its token is all that guards the
             * board: long and random, and only on a dashboard. The app makes 32 hex
             * characters; a broken or modified client could sync "1234", and anyone
             * could then guess the address.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, Map<String, Object> fields) {
                if (fields != null
                        && fields.containsKey("layout")
                        // `Set.of` throws on `contains(null)`: a null layout was a 500.
                        && (fields.get("layout") == null || !LAYOUTS.contains(fields.get("layout")))) {
                    // A layout no client knows is refused where it comes in.
                    return Optional.of(LAYOUT_INVALID);
                }
                if (fields == null || fields.get("token") == null) {
                    return Optional.empty();
                }
                String kind = fields.containsKey("kind")
                        ? String.valueOf(fields.get("kind"))
                        : db.select(BOARD.KIND).from(BOARD).where(BOARD.ID.eq(entityId)).fetchOne(BOARD.KIND);
                String token = fields.get("token").toString();
                boolean strong = TOKEN.matcher(token).matches() && varied(token);
                return strong && "DASHBOARD".equals(kind) ? Optional.empty() : Optional.of(TOKEN_INVALID);
            }

            /** The token is a session of the owner: for nobody else's devices. */
            @Override
            public java.util.Set<String> secretFields() {
                return java.util.Set.of("token");
            }

            /** With a board go its tiles. */
            @Override
            public List<Ref> alsoDeleted(UUID entityId) {
                return db.select(WIDGET.ID)
                        .from(WIDGET)
                        .where(WIDGET.BOARD_ID.eq(entityId))
                        .and(WIDGET.DELETED_AT.isNull())
                        .fetch(WIDGET.ID)
                        .stream()
                        .map(id -> new Ref(WIDGET_TYPE, id))
                        .toList();
            }
        };
    }

    @Bean
    SyncType widgetSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return WIDGET_TYPE;
            }

            @Override
            public Table<?> table() {
                return WIDGET;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.text("kind", WIDGET.KIND),
                        // Replaced as a whole: a configuration is a form, not a bucket
                        // that several devices independently drop things into.
                        SyncField.json("config", WIDGET.CONFIG),
                        SyncField.integer("gridX", WIDGET.GRID_X),
                        SyncField.integer("gridY", WIDGET.GRID_Y),
                        SyncField.integer("gridW", WIDGET.GRID_W),
                        SyncField.integer("gridH", WIDGET.GRID_H),
                        SyncField.integer("position", WIDGET.POSITION));
            }

            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(BOARD_TYPE, WIDGET.BOARD_ID));
            }
        };
    }
}
