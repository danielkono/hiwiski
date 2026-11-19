package de.danielkononov.hiwiski.dashboard;

import static de.danielkononov.hiwiski.db.generated.Tables.BOARD;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The acceptance case for boards and the dashboard.
 *
 * <p>"Set up a board from the phone and open it on the wall tablet via its address —
 * <strong>without signing in</strong> […]. <strong>Regenerating the address kills the old
 * one immediately.</strong> A widget type the app does not know shows a placeholder."
 */
@IntegrationTest
class DashboardIT {

    private static final String BOARD_TYPE = "BOARD";
    private static final String WIDGET_TYPE = "WIDGET";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    @org.springframework.beans.factory.annotation.Value("${local.server.port}")
    int port;

    private Family.Session anna;
    private SyncClient phone;
    private UUID boardId;
    private String token;

    @BeforeEach
    void aBoardFromThePhone() {
        anna = Family.setUp(rest);
        phone = new SyncClient(rest, anna);

        boardId = UUID.randomUUID();
        token = "tablet-" + UUID.randomUUID();
        phone.push(SyncClient.mutation(BOARD_TYPE, boardId, null, Map.of(
                "kind", "DASHBOARD",
                "name", "Küche",
                "layout", "GRID",
                "columns", 4,
                "token", token)));
    }

    private void widget(String kind, Map<String, Object> config, int x, int y) {
        phone.push(SyncClient.withContainer(
                SyncClient.mutation(WIDGET_TYPE, UUID.randomUUID(), null, Map.of(
                        "kind", kind,
                        "config", config,
                        "gridX", x,
                        "gridY", y,
                        "gridW", 2,
                        "gridH", 1)),
                BOARD_TYPE,
                boardId));
    }

    private Map<?, ?> fetch(String token, org.springframework.http.HttpStatus status) {
        return rest.get()
                .uri("/api/v1/boards/" + token)
                // **Without signing in** -- no header, no token in the keychain.
                .exchange()
                .expectStatus()
                .isEqualTo(status)
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    @Test
    void theWallTabletOpensTheBoardWithoutSigningIn() {
        widget("CLOCK", Map.of("seconds", false), 0, 0);
        widget("CALENDAR", Map.of("days", 3), 2, 0);

        var board = fetch(token, org.springframework.http.HttpStatus.OK);

        assertThat(board.get("name")).isEqualTo("Küche");
        assertThat(board.get("layout")).isEqualTo("GRID");
        assertThat(board.get("columns")).isEqualTo(4);

        @SuppressWarnings("unchecked")
        var widgets = (List<Map<String, Object>>) board.get("widgets");
        assertThat(widgets).hasSize(2);
        assertThat(widgets).extracting(w -> w.get("kind")).containsExactly("CLOCK", "CALENDAR");
        // The configuration comes along -- otherwise the tablet would not know what to
        // show.
        assertThat(widgets.getFirst().get("config")).isEqualTo(Map.of("seconds", false));
    }

    /**
     * The tiles' content comes from the board, in its owner's name: a
     * wall tablet without a sign-in showed every data tile empty.
     */
    @Test
    @SuppressWarnings("unchecked")
    void theWallTabletGetsWhatItsTilesShow() {
        UUID kitchen = UUID.randomUUID();
        UUID school = UUID.randomUUID();
        UUID dentist = UUID.randomUUID();
        UUID holidays = UUID.randomUUID();
        UUID groceries = UUID.randomUUID();
        UUID milk = UUID.randomUUID();
        phone.push(SyncClient.mutation(
                "CALENDAR", kitchen, null, Map.of("name", "Family", "colorToken", "BLUE", "kind", "LOCAL")));
        phone.push(SyncClient.mutation(
                "CALENDAR", school, null, Map.of("name", "School", "colorToken", "RED", "kind", "LOCAL")));
        phone.push(SyncClient.withContainer(
                SyncClient.mutation("EVENT", dentist, null, Map.of(
                        "title", "Dentist", "timeForm", "TIMED", "startsAt", "2026-10-12T08:00:00Z")),
                "CALENDAR",
                kitchen));
        phone.push(SyncClient.withContainer(
                SyncClient.mutation("EVENT", holidays, null, Map.of(
                        "title", "Holidays", "timeForm", "ALL_DAY", "startDate", "2026-10-19")),
                "CALENDAR",
                school));
        phone.push(SyncClient.mutation(
                "TODO_LIST", groceries, null, Map.of("name", "Groceries", "kind", "SHOPPING")));
        phone.push(SyncClient.withContainer(
                SyncClient.mutation("TODO", milk, null, Map.of("title", "Milk", "status", "OPEN")),
                "TODO_LIST",
                groceries));
        widget("CALENDAR", Map.of("calendarIds", List.of(kitchen.toString())), 0, 0);
        widget("SHOPPING_LIST", Map.of("listId", groceries.toString()), 2, 0);

        var content = rest.get()
                .uri("/api/v1/boards/" + token + "/content")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        var items = (List<Map<String, Object>>) content.get("items");
        assertThat(items)
                .extracting(item -> item.get("entityId"))
                .containsExactly(kitchen.toString(), dentist.toString(), groceries.toString(), milk.toString());
        assertThat(items.get(1).get("containerId")).isEqualTo(kitchen.toString());
    }

    @Test
    void anUnknownWidgetTypeComesThrough() {
        // **An unknown widget type shows a placeholder and never crashes.** An installed
        // app can be older than the server -- so the server must not
        // swallow it.
        widget("WEATHER_STATION_2031", Map.of("location", "Berlin"), 0, 0);

        var board = fetch(token, org.springframework.http.HttpStatus.OK);
        @SuppressWarnings("unchecked")
        var widgets = (List<Map<String, Object>>) board.get("widgets");

        assertThat(widgets).hasSize(1);
        assertThat(widgets.getFirst().get("kind")).isEqualTo("WEATHER_STATION_2031");
    }

    @Test
    void aRegeneratedAddressKillsTheOldOneImmediately() {
        assertThat(fetch(token, org.springframework.http.HttpStatus.OK)).isNotNull();

        long version = db.select(BOARD.VERSION)
                .from(BOARD)
                .where(BOARD.ID.eq(boardId))
                .fetchOne(BOARD.VERSION);
        String fresh = "tablet-" + UUID.randomUUID();
        phone.push(SyncClient.mutation(BOARD_TYPE, boardId, version, Map.of("token", fresh)));

        // Immediately, not after a grace period: whoever revokes the address wants it gone
        // now.
        fetch(token, org.springframework.http.HttpStatus.NOT_FOUND);
        assertThat(fetch(fresh, org.springframework.http.HttpStatus.OK)).isNotNull();
    }

    /**
     * The stream the wall tablet opened with the old address ends too. It used to hear of
     * every change until it timed out half an hour later, while the address itself
     * already opened nothing.
     */
    @Test
    void aRegeneratedAddressEndsTheStreamOpenedWithIt() throws Exception {
        var ticket = rest.post()
                .uri("/api/v1/boards/" + token + "/ticket")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("ticket");
        var http = java.net.http.HttpClient.newHttpClient();
        var lines = new java.util.concurrent.LinkedBlockingQueue<String>();
        http.sendAsync(
                        java.net.http.HttpRequest.newBuilder(java.net.URI.create(
                                        "http://localhost:" + port + "/api/v1/events?ticket=" + ticket))
                                .header("Accept", "text/event-stream")
                                .build(),
                        java.net.http.HttpResponse.BodyHandlers.ofLines())
                .thenAccept(response -> response.body().forEach(lines::add));
        try {
            await(lines, "event:seq");

            long version = db.select(BOARD.VERSION)
                    .from(BOARD)
                    .where(BOARD.ID.eq(boardId))
                    .fetchOne(BOARD.VERSION);
            phone.push(SyncClient.mutation(
                    BOARD_TYPE, boardId, version, Map.of("token", "tablet-" + UUID.randomUUID())));

            await(lines, "event:revoked");
        } finally {
            http.shutdownNow();
        }
    }

    /** The next line that starts with [prefix], within ten seconds. */
    private static void await(java.util.concurrent.BlockingQueue<String> lines, String prefix)
            throws InterruptedException {
        long until = System.nanoTime() + java.time.Duration.ofSeconds(10).toNanos();
        while (true) {
            String line = lines.poll(until - System.nanoTime(), java.util.concurrent.TimeUnit.NANOSECONDS);
            if (line == null) {
                throw new AssertionError("no " + prefix + " within ten seconds");
            }
            if (line.startsWith(prefix)) {
                return;
            }
        }
    }

    /** A disabled member's board address stops working like their devices do. */
    @Test
    void aDisabledOwnersAddressNoLongerWorks() {
        fetch(token, org.springframework.http.HttpStatus.OK);

        db.update(de.danielkononov.hiwiski.db.generated.Tables.MEMBER)
                .set(de.danielkononov.hiwiski.db.generated.Tables.MEMBER.DISABLED_AT, java.time.OffsetDateTime.now())
                .where(de.danielkononov.hiwiski.db.generated.Tables.MEMBER.ID.eq(anna.memberId()))
                .execute();

        fetch(token, org.springframework.http.HttpStatus.NOT_FOUND);
        rest.post()
                .uri("/api/v1/boards/" + token + "/ticket")
                .exchange()
                .expectStatus()
                .isNotFound();
    }

    /** The token is all that guards the address: long, and only on a dashboard. */
    @Test
    @SuppressWarnings("unchecked")
    void aWeakTokenOrOneOnAnotherBoardIsRefused() {
        var weak = phone.push(SyncClient.mutation(BOARD_TYPE, UUID.randomUUID(), null, Map.of(
                "kind", "DASHBOARD", "name", "Flur", "layout", "GRID", "columns", 4, "token", "1234")));
        var start = phone.push(SyncClient.mutation(BOARD_TYPE, UUID.randomUUID(), null, Map.of(
                "kind", "START", "name", "Start", "layout", "FLOW", "columns", 4,
                "token", "start-" + UUID.randomUUID())));

        assertThat(weak.getFirst().get("code")).isEqualTo("dashboard.token_invalid");
        assertThat(start.getFirst().get("code")).isEqualTo("dashboard.token_invalid");
    }

    /** A layout no client knows is refused -- and one already stored does not break the board. */
    @Test
    void anUnknownLayoutBreaksNothing() {
        var refused = phone.push(SyncClient.mutation(BOARD_TYPE, UUID.randomUUID(), null, Map.of(
                "kind", "DASHBOARD", "name", "Flur", "layout", "MASONRY", "columns", 4,
                "token", "flur-" + UUID.randomUUID())));
        assertThat(refused.getFirst().get("code")).isEqualTo("dashboard.layout_invalid");

        db.update(de.danielkononov.hiwiski.db.generated.Tables.BOARD)
                .set(de.danielkononov.hiwiski.db.generated.Tables.BOARD.LAYOUT, "MASONRY")
                .where(de.danielkononov.hiwiski.db.generated.Tables.BOARD.ID.eq(boardId))
                .execute();
        assertThat(fetch(token, org.springframework.http.HttpStatus.OK).get("layout")).isEqualTo("GRID");
    }

    @Test
    void aMadeUpAddressLooksLikeARevokedOne() {
        fetch("does-not-exist", org.springframework.http.HttpStatus.NOT_FOUND);
    }

    @Test
    void theTabletGetsATicketForTheStream() {
        // The stream needs a ticket because an SSE connection cannot be opened with a
        // header — and it runs in the owner's name, so the board never shows
        // what the owner would not be allowed to see.
        var ticket = rest.post()
                .uri("/api/v1/boards/" + token + "/ticket")
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        assertThat(ticket.get("ticket")).asString().isNotEmpty();
        assertThat(ticket.get("expiresAt")).isNotNull();
    }

    @Test
    void exactlyOneBoardOfEachKindPerMember() {
        // **Exactly one start board and exactly one dashboard per member**. Both are
        // created automatically on first open -- an empty screen with a "Create board"
        // button would be a question with only one answer.
        var second = phone.push(SyncClient.mutation(BOARD_TYPE, UUID.randomUUID(), null, Map.of(
                "kind", "DASHBOARD",
                "name", "Another one")));

        assertThat(second.getFirst().get("status"))
                .describedAs("the server rejects a second dashboard")
                .isEqualTo("rejected");
        assertThat(db.fetchCount(BOARD, BOARD.DELETED_AT.isNull())).isEqualTo(1);
    }
}
