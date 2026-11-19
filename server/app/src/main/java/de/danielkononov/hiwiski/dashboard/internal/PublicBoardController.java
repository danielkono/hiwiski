package de.danielkononov.hiwiski.dashboard.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.BOARD;
import static de.danielkononov.hiwiski.db.generated.Tables.CALENDAR;
import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.WIDGET;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.api.DashboardApi;
import de.danielkononov.hiwiski.api.model.BoardContent;
import de.danielkononov.hiwiski.api.model.BoardView;
import de.danielkononov.hiwiski.api.model.ChangeEnvelope;
import de.danielkononov.hiwiski.api.model.DashboardTicket;
import de.danielkononov.hiwiski.api.model.WidgetView;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.VisibleItems;
import java.util.Map;
import java.util.UUID;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.impl.DSL;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.ObjectMapper;

/**
 * The dashboard at its own address.
 *
 * <p><strong>No login, does not expire, revocable</strong>. A wall tablet as a
 * full account would bring along a lot of questions nobody wants to answer — a token
 * without expiry in the keychain, an app that never logs out, a way out of full screen
 * without a keyboard. The address solves all three.
 *
 * <p><strong>The session of this address is restricted to the board's owner</strong>
 * and can do nothing they cannot: the stream ticket runs in their name, and the stream
 * filters as it would for them. A board therefore never shows anything its owner would
 * not be allowed to see.
 *
 * <p>"Regenerate address" needs no endpoint of its own: the token is a field on the
 * board and goes through sync. Whoever overwrites it kills the old address
 * <strong>immediately</strong> — the query below no longer finds it. A stream opened
 * with the old address runs on until it times out; it carries only change positions,
 * and the content behind them needs a valid address.
 */
@RestController
class PublicBoardController implements DashboardApi {

    private final DSLContext db;
    private final DashboardAddresses addresses;
    private final VisibleItems visible;
    private static final String DASHBOARD = "DASHBOARD";

    /** The application's mapper: one of its own ignored the configured modules. */
    private final ObjectMapper mapper;

    PublicBoardController(
            DSLContext db, DashboardAddresses addresses, VisibleItems visible, ObjectMapper mapper) {
        this.db = db;
        this.addresses = addresses;
        this.visible = visible;
        this.mapper = mapper;
    }

    @Override
    public ResponseEntity<BoardView> getPublicBoard(String token) {
        var board = board(token);

        var widgets = db.selectFrom(WIDGET)
                .where(WIDGET.BOARD_ID.eq(board.getId()))
                .and(WIDGET.DELETED_AT.isNull())
                .orderBy(WIDGET.GRID_Y.asc(), WIDGET.GRID_X.asc(), WIDGET.POSITION.asc())
                .fetch()
                .map(row -> {
                    var widget = new WidgetView(
                            row.getId(),
                            row.getKind(),
                            row.getGridX(),
                            row.getGridY(),
                            row.getGridW(),
                            row.getGridH(),
                            row.getPosition());
                    widget.setConfig(config(row.getConfig()));
                    return widget;
                });

        var view = new BoardView(
                board.getId(),
                board.getOwnerId(),
                layout(board.getLayout()),
                board.getColumns(),
                widgets);
        view.setName(board.getName());
        return ResponseEntity.ok(view);
    }

    /**
     * What the tiles name: their calendars and events, their lists and tasks, their
     * pages -- in the owner's name, as a snapshot pull would deliver them to the owner.
     * A calendar tile without a choice shows every calendar, a lists tile
     * without one every list, a recipe tile picks among all recipes.
     */
    @Override
    public ResponseEntity<BoardContent> getPublicBoardContent(String token) {
        var board = board(token);
        var calendars = new Wanted();
        var lists = new Wanted();
        var pages = new Wanted();
        boolean recipes = false;
        for (var row : db.selectFrom(WIDGET)
                .where(WIDGET.BOARD_ID.eq(board.getId()))
                .and(WIDGET.DELETED_AT.isNull())
                .fetch()) {
            Map<String, Object> config = config(row.getConfig());
            switch (row.getKind()) {
                case "CALENDAR", "CALENDAR_WEEK" -> calendars.addAll(ids(config.get("calendarIds")));
                case "TODO_LISTS" -> lists.addAll(ids(config.get("listIds")));
                case "TODO_LIST", "SHOPPING_LIST", "KANBAN_BOARD" -> lists.add(id(config.get("listId")));
                case "WIKI_PAGE" -> pages.add(id(config.get("pageId")));
                case "RECIPE" -> recipes = true;
                default -> {
                    // A clock or a note shows nothing it would have to read.
                }
            }
        }

        UUID owner = board.getOwnerId();
        var items = new java.util.ArrayList<ChangeEnvelope>();
        if (calendars.asked()) {
            items.addAll(visible.visibleTo(owner, "CALENDAR", calendars.of(CALENDAR.ID)));
            items.addAll(visible.visibleTo(owner, "EVENT", calendars.of(EVENT.CALENDAR_ID)));
        }
        if (lists.asked()) {
            items.addAll(visible.visibleTo(owner, "TODO_LIST", lists.of(TODO_LIST.ID)));
            items.addAll(visible.visibleTo(owner, "TODO", lists.of(TODO.LIST_ID)));
        }
        if (pages.asked() || recipes) {
            Condition wanted = DSL.falseCondition();
            if (pages.asked()) {
                wanted = wanted.or(pages.of(WIKI_PAGE.ID));
            }
            if (recipes) {
                wanted = wanted.or(WIKI_PAGE.KIND.eq("RECIPE"));
            }
            items.addAll(visible.visibleTo(owner, "WIKI_PAGE", wanted));
        }
        return ResponseEntity.ok(new BoardContent(items));
    }

    /**
     * The items of one kind the tiles ask for: some by ID, or -- a tile without a
     * choice -- all of them.
     */
    private static final class Wanted {
        private final java.util.Set<UUID> ids = new java.util.LinkedHashSet<>();
        private boolean asked;
        private boolean all;

        void add(UUID id) {
            asked = true;
            if (id != null) {
                ids.add(id);
            }
        }

        /** An empty choice is "all". */
        void addAll(java.util.List<UUID> chosen) {
            asked = true;
            if (chosen.isEmpty()) {
                all = true;
            }
            ids.addAll(chosen);
        }

        boolean asked() {
            return asked;
        }

        Condition of(org.jooq.Field<UUID> column) {
            return all ? DSL.trueCondition() : column.in(ids);
        }
    }

    private static UUID id(Object value) {
        try {
            return value instanceof String text ? UUID.fromString(text) : null;
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static java.util.List<UUID> ids(Object value) {
        if (!(value instanceof java.util.List<?> values)) {
            return java.util.List.of();
        }
        return values.stream().map(PublicBoardController::id).filter(java.util.Objects::nonNull).toList();
    }

    @Override
    public ResponseEntity<DashboardTicket> createDashboardTicket(String token) {
        var board = board(token);
        // In the owner's name: the stream then filters as it would for them. And bound
        // to the address: it ends when the address does.
        var issued = addresses.ticket(board.getId(), board.getOwnerId(), token);
        return ResponseEntity.ok(new DashboardTicket(issued.value(), issued.expiresAt()));
    }

    /**
     * A newly generated token kills the old address immediately -- and disabling the
     * owner does too: the address can do nothing its owner cannot, and a member who left
     * the household keeps no wall tablet showing the family's board.
     */
    private de.danielkononov.hiwiski.db.generated.tables.records.BoardRecord board(String token) {
        var board = db.select(BOARD.fields())
                .from(BOARD)
                .join(MEMBER)
                .on(MEMBER.ID.eq(BOARD.OWNER_ID))
                .where(BOARD.TOKEN.eq(token))
                // Only a dashboard has an address; a token on another board, synced
                // by a broken client, opens nothing.
                .and(BOARD.KIND.eq(DASHBOARD))
                .and(BOARD.DELETED_AT.isNull())
                .and(MEMBER.DISABLED_AT.isNull())
                .fetchOneInto(BOARD);
        if (board == null) {
            // A revoked address looks like a made-up one.
            throw HiwiskiException.notFound("dashboard.board_not_found");
        }
        return board;
    }

    /**
     * A layout this server does not know -- from a newer or broken client -- shows the
     * board as a grid, which is what a dashboard is, instead of failing the whole board
     * with a 400 on the wall tablet. A broken tile is tolerated the same way.
     */
    private static BoardView.LayoutEnum layout(String value) {
        try {
            return BoardView.LayoutEnum.fromValue(value);
        } catch (IllegalArgumentException unknown) {
            return BoardView.LayoutEnum.GRID;
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> config(org.jooq.JSONB value) {
        if (value == null || value.data() == null) {
            return Map.of();
        }
        try {
            return mapper.readValue(value.data(), Map.class);
        } catch (RuntimeException e) {
            // A broken configuration must not cost the whole board -- the widget then
            // shows its placeholder.
            return Map.of();
        }
    }
}
