package de.danielkononov.hiwiski.link;

import static de.danielkononov.hiwiski.db.generated.Tables.EVENT;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Links across module boundaries.
 *
 * <p>{@code WikiTreeIT} tests the page → page case. This is about what makes the reverse
 * direction worthwhile in the first place: an <strong>event</strong> does the same without
 * {@code link} knowing it — and the response carries the <strong>number</strong>, because
 * the info bar shows it on every row.
 */
@IntegrationTest
class LinkIT {

    private static final String PAGE = "WIKI_PAGE";
    private static final String CALENDAR = "CALENDAR";
    private static final String EVENT_TYPE = "EVENT";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private SyncClient annasDevice;
    private UUID calendar;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        annasDevice = new SyncClient(rest, anna);
        calendar = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(CALENDAR, calendar, null, Map.of("name", "Familie")));
    }

    private UUID page(String title, String content) {
        UUID id = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                PAGE, id, null, Map.of("title", title, "kind", "PAGE", "content", content)));
        return id;
    }

    private UUID event(String title, String note) {
        UUID id = UUID.randomUUID();
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        EVENT_TYPE,
                        id,
                        null,
                        Map.of(
                                "title", title,
                                "description", note,
                                "timeForm", "TIMED",
                                "startsAt", "2026-10-19T17:00:00Z",
                                "endsAt", "2026-10-19T18:00:00Z")),
                CALENDAR,
                calendar));
        return id;
    }

    private Map<?, ?> links(String itemType, UUID itemId) {
        return rest.get()
                .uri("/api/v1/links/" + itemType + "/" + itemId)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> direction(Map<?, ?> body, String name) {
        return (List<Map<String, Object>>) body.get(name);
    }

    @Test
    void anEventsNoteIsParsedAndTheLinkCarriesTheNumber() {
        UUID target = page("Rezept", "");
        String key = db.select(WIKI_PAGE.ENTITY_KEY)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(target))
                .fetchOne(WIKI_PAGE.ENTITY_KEY);

        UUID dinner = event("Abendessen", "Wir kochen #" + key + ".");
        FollowUps.await(db);

        var outgoing = direction(links(EVENT_TYPE, dinner), "outgoing");
        assertThat(outgoing)
                .describedAs("without CalendarLinkSource #EVT would not be a link and a note would not be text")
                .hasSize(1);
        assertThat(outgoing.getFirst().get("title")).isEqualTo("Rezept");
        // The info bar's mono number. It was once `null` -- and so the row showed only the
        // title.
        assertThat(outgoing.getFirst().get("entityKey")).isEqualTo(key);

        var incoming = direction(links(PAGE, target), "incoming");
        assertThat(incoming).hasSize(1);
        assertThat(incoming.getFirst().get("itemType")).isEqualTo(EVENT_TYPE);
        assertThat(incoming.getFirst().get("title")).isEqualTo("Abendessen");
    }

    @Test
    void aListIsATargetByItsAddress() {
        UUID shopping = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "TODO_LIST", shopping, null, Map.of("name", "Einkauf", "kind", "SHOPPING")));
        UUID weekend = page("Wochenende", "Vorher [Einkauf](hiwiski://todo_list/" + shopping + ").");
        FollowUps.await(db);

        var outgoing = direction(links(PAGE, weekend), "outgoing");
        assertThat(outgoing)
                .describedAs("without TodoListLinkSource a list's address would not be a link")
                .hasSize(1);
        assertThat(outgoing.getFirst().get("itemType")).isEqualTo("TODO_LIST");
        assertThat(outgoing.getFirst().get("title")).isEqualTo("Einkauf");
    }

    @Test
    void aListGetsItsNumberAndIsReachableByIt() {
        UUID shopping = UUID.randomUUID();
        annasDevice.push(SyncClient.mutation(
                "TODO_LIST", shopping, null, Map.of("name", "Einkauf", "kind", "SHOPPING")));
        String key = db.select(TODO_LIST.ENTITY_KEY)
                .from(TODO_LIST)
                .where(TODO_LIST.ID.eq(shopping))
                .fetchOne(TODO_LIST.ENTITY_KEY);
        assertThat(key).describedAs("a list gets a number of its own on the first sync").isEqualTo("LST-1");

        UUID weekend = page("Wochenende", "Vorher #" + key + " abarbeiten.");
        FollowUps.await(db);

        var outgoing = direction(links(PAGE, weekend), "outgoing");
        assertThat(outgoing).hasSize(1);
        assertThat(outgoing.getFirst().get("itemType")).isEqualTo("TODO_LIST");
        assertThat(outgoing.getFirst().get("entityKey")).isEqualTo(key);
    }

    @Test
    void anEventIsReachableByItsNumber() {
        UUID dinner = event("Abendessen", "");
        String key = db.select(EVENT.ENTITY_KEY)
                .from(EVENT)
                .where(EVENT.ID.eq(dinner))
                .fetchOne(EVENT.ENTITY_KEY);
        assertThat(key).describedAs("an event created in the app gets its number").startsWith("EVT-");

        page("Einkauf", "Vorher einkaufen, siehe #" + key + ".");
        FollowUps.await(db);

        var incoming = direction(links(EVENT_TYPE, dinner), "incoming");
        assertThat(incoming).hasSize(1);
        assertThat(incoming.getFirst().get("title")).isEqualTo("Einkauf");
    }

    @Test
    void theTitleIsCurrent() {
        UUID target = page("Router", "");
        String key = db.select(WIKI_PAGE.ENTITY_KEY)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(target))
                .fetchOne(WIKI_PAGE.ENTITY_KEY);
        UUID source = page("Internet", "Credentials are in #" + key + ".");
        FollowUps.await(db);

        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(target))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.mutation(PAGE, target, version, Map.of("title", "Fritzbox")));
        FollowUps.await(db);

        // Not the text that applied when writing. The text still holds
        // the number -- the chip shows the new title.
        assertThat(direction(links(PAGE, source), "outgoing").getFirst().get("title"))
                .isEqualTo("Fritzbox");
    }

    @Test
    void whoeverMayNotSeeTheItemGetsFourOhFour() {
        UUID secret = page("Router", "");

        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var joined = rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", "Ben",
                        "username", "ben",
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", "Bens Tablet", "platform", "ANDROID")))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var ben = Family.toSession(joined);

        // 404 and not 403, and already when asking for the links: otherwise a non-empty
        // response would reveal that the page exists.
        rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + secret)
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isNotFound();
    }

    /** The info bar lists a page's references in the order the text names them. */
    @Test
    void referencesComeInTextOrder() {
        UUID zebra = page("Zebra", "");
        UUID apfel = page("Apfel", "");
        UUID mango = page("Mango", "");
        UUID source = page("Quelle", "Erst [M](hiwiski://wiki_page/" + mango + "), dann [Z](hiwiski://wiki_page/"
                + zebra + ") und zuletzt [A](hiwiski://wiki_page/" + apfel + ").");
        FollowUps.await(db);

        assertThat(direction(links(PAGE, source), "outgoing"))
                .extracting(ref -> ref.get("title"))
                .containsExactly("Mango", "Zebra", "Apfel");
    }
}
