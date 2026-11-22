package de.danielkononov.hiwiski.wiki;

import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_EDGE;
import static de.danielkononov.hiwiski.db.generated.Tables.MINDMAP_NODE;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.LinkedHashMap;
import java.util.HashMap;
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
 * A mind map's elements and connections are items of their own in their page: each
 * field of each element is conflict-checked on its own, they inherit the page's share,
 * and they go and come back with the page.
 */
@IntegrationTest
class MindmapIT {

    private static final String PAGE = "WIKI_PAGE";
    private static final String NODE = "MINDMAP_NODE";
    private static final String EDGE = "MINDMAP_EDGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient phone;
    private SyncClient laptop;
    private SyncClient bensTablet;
    private UUID map;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        phone = new SyncClient(rest, anna);
        laptop = new SyncClient(rest, Family.login(rest, "anna", "geheim-genug", "Laptop"));
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        ben = Family.toSession(rest.post()
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
                .getResponseBody());
        bensTablet = new SyncClient(rest, ben);
        map = page("Urlaub", "MINDMAP");
    }

    private UUID page(String title, String kind) {
        UUID id = UUID.randomUUID();
        var result = phone.push(SyncClient.mutation(PAGE, id, null, Map.of("title", title, "kind", kind)));
        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        return id;
    }

    private Map<String, Object> onMap(String type, UUID id, Long base, Map<String, Object> fields) {
        return SyncClient.withContainer(SyncClient.mutation(type, id, base, fields), PAGE, map);
    }

    private UUID node(SyncClient device, String text) {
        UUID id = UUID.randomUUID();
        var result = device.push(onMap(NODE, id, null, Map.of(
                "kind", "PLAIN", "x", 10, "y", 20, "width", 160, "height", 80, "layer", 1, "text", text)));
        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        return id;
    }

    private Map<String, Object> edge(UUID from, UUID to) {
        return onMap(EDGE, UUID.randomUUID(), null, Map.of("fromId", from.toString(), "toId", to.toString()));
    }

    private void share(String level) {
        rest.put()
                .uri("/api/v1/items/" + PAGE + "/" + map + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER",
                        "subjectId", ben.memberId().toString(),
                        "level", level))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    private static long version(Map<String, Object> result) {
        return ((Number) result.get("version")).longValue();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> merged(List<Map<String, Object>> changes, UUID id) {
        Map<String, Object> state = new LinkedHashMap<>();
        changes.stream()
                .filter(change -> id.toString().equals(change.get("entityId")))
                .forEach(change -> {
                    state.put("op", change.get("op"));
                    if (change.get("fields") != null) {
                        state.putAll((Map<String, Object>) change.get("fields"));
                    }
                });
        return state;
    }

    private boolean deleted(org.jooq.Table<?> table, UUID id) {
        return db.fetchExists(db.selectOne()
                .from(table)
                .where(org.jooq.impl.DSL.field("id", UUID.class).eq(id))
                .and(org.jooq.impl.DSL.field("deleted_at").isNotNull()));
    }

    @Test
    void elementsAndConnectionsArriveInTheirPage() {
        UUID first = node(phone, "Meer");
        UUID second = node(phone, "Berge");
        var connected = phone.push(edge(first, second));
        assertThat(connected.getFirst().get("status")).isEqualTo("applied");

        var changes = laptop.pullAll();
        assertThat(merged(changes, first)).containsEntry("text", "Meer").containsEntry("width", 160);
        assertThat(changes.stream()
                        .filter(change -> first.toString().equals(change.get("entityId")))
                        .findFirst()
                        .orElseThrow())
                .containsEntry("containerType", PAGE)
                .containsEntry("containerId", map.toString());

        // A device that starts afresh gets them in the snapshot, after their page.
        var snapshot = new SyncClient(rest, Family.login(rest, "anna", "geheim-genug", "Tablet")).pullSnapshot(50);
        assertThat(merged(snapshot, second)).containsEntry("text", "Berge");
        assertThat(snapshot.stream().map(change -> change.get("entityType")).toList())
                .contains(NODE, EDGE);
    }

    @Test
    void twoPeopleChangingDifferentElementsOrFieldsBothGetThroughTheSameFieldConflicts() {
        UUID first = node(phone, "Meer");
        UUID second = node(phone, "Berge");
        var known = laptop.pullAll();
        long firstVersion = known.stream()
                .filter(change -> first.toString().equals(change.get("entityId")))
                .mapToLong(change -> ((Number) change.get("version")).longValue())
                .max()
                .orElseThrow();
        long secondVersion = known.stream()
                .filter(change -> second.toString().equals(change.get("entityId")))
                .mapToLong(change -> ((Number) change.get("version")).longValue())
                .max()
                .orElseThrow();

        // The phone moves the first element, the laptop moves the second and recolours
        // the first: nothing collides.
        assertThat(phone.push(onMap(NODE, first, firstVersion, Map.of("x", 300, "y", 400)))
                        .getFirst()
                        .get("status"))
                .isEqualTo("applied");
        var fromLaptop = laptop.push(
                onMap(NODE, second, secondVersion, Map.of("x", 50)),
                onMap(NODE, first, firstVersion, Map.of("color", "#3B6939")));
        assertThat(fromLaptop).allSatisfy(result -> assertThat(result.get("status")).isEqualTo("applied"));

        // The same field of the same element: that element's conflict, with the
        // server's value -- the rest of the map is not touched.
        var clash = laptop.push(onMap(NODE, first, firstVersion, Map.of("x", 999)));
        assertThat(clash.getFirst().get("status")).isEqualTo("conflict");
        assertThat(List.copyOf((List<?>) clash.getFirst().get("conflictFields"))).isEqualTo(List.of("x"));
        assertThat(((Map<?, ?>) clash.getFirst().get("serverFields")).get("x")).isEqualTo(300);
    }

    @Test
    void aColourIsATokenOrAnRgbValue() {
        UUID element = UUID.randomUUID();
        long base = version(phone.push(onMap(NODE, element, null, Map.of("kind", "PLAIN", "color", "TEAL")))
                .getFirst());
        var own = phone.push(onMap(NODE, element, base, Map.of("color", "#a1B2c3", "textColor", "SLATE")));
        assertThat(own.getFirst().get("status")).isEqualTo("applied");
        // See-through: with its alpha.
        var clear = phone.push(onMap(NODE, element, null, Map.of("color", "#a1B2c340")));
        assertThat(clear.getFirst().get("status")).isEqualTo("applied");

        for (Object wrong : List.of("rot", "#12345", "rgb(1,2,3)", "#1234567", "#123456789")) {
            var result = phone.push(onMap(NODE, element, null, Map.of("color", wrong)));
            assertThat(result.getFirst().get("status")).describedAs("%s", wrong).isEqualTo("rejected");
            var text = phone.push(onMap(NODE, element, null, Map.of("textColor", wrong)));
            assertThat(text.getFirst().get("status")).describedAs("text %s", wrong).isEqualTo("rejected");
        }
        var tooSmall = phone.push(onMap(NODE, element, null, Map.of("width", 0)));
        assertThat(tooSmall.getFirst().get("status")).isEqualTo("rejected");
        var elsewhere = phone.push(onMap(NODE, element, null, Map.of("target", "https://example.org")));
        assertThat(elsewhere.getFirst().get("status")).isEqualTo("rejected");
        var stroke = phone.push(onMap(NODE, element, null, Map.of("points", "0,0 5000,10000 10000,0", "strokeWidth", 4)));
        assertThat(stroke.getFirst().get("status")).isEqualTo("applied");
        for (Object scribble : List.of("", "0,0 ", "1;2", "0,0  1,1", "a,b", "123456,1")) {
            var result = phone.push(onMap(NODE, element, null, Map.of("points", scribble)));
            assertThat(result.getFirst().get("status")).describedAs("points %s", scribble).isEqualTo("rejected");
        }
        // Some eight thousand points: long, and still read without running out of stack.
        var longStroke = phone.push(onMap(NODE, element, null, Map.of(
                "points", String.join(" ", java.util.Collections.nCopies(8_000, "10000,10000")))));
        assertThat(longStroke.getFirst().get("status")).isEqualTo("applied");
        var thin = phone.push(onMap(NODE, element, null, Map.of("strokeWidth", 0)));
        assertThat(thin.getFirst().get("status")).isEqualTo("rejected");
        // A text size by name, or of its own in pixels.
        for (Object size : List.of("XL", "18")) {
            var result = phone.push(onMap(NODE, element, null, Map.of("textSize", size)));
            assertThat(result.getFirst().get("status")).describedAs("size %s", size).isEqualTo("applied");
        }
        for (Object size : List.of("huge", "1", "9999", "-3")) {
            var result = phone.push(onMap(NODE, element, null, Map.of("textSize", size)));
            assertThat(result.getFirst().get("status")).describedAs("size %s", size).isEqualTo("rejected");
        }
        var view = phone.push(onMap(NODE, element, null, Map.of("linkView", "CONTENT")));
        assertThat(view.getFirst().get("status")).isEqualTo("applied");
        var unreadable = phone.push(onMap(NODE, element, null, Map.of("linkView", "alles")));
        assertThat(unreadable.getFirst().get("status")).isEqualTo("rejected");
    }

    @Test
    void aConnectionJoinsTwoLivingElementsOfItsPage() {
        UUID first = node(phone, "Meer");
        UUID second = node(phone, "Berge");

        var toItself = phone.push(edge(first, first));
        assertThat(toItself.getFirst().get("code")).isEqualTo("wiki.mindmap_element_gone");

        UUID other = page("Anderswo", "MINDMAP");
        UUID stranger = UUID.randomUUID();
        phone.push(SyncClient.withContainer(
                SyncClient.mutation(NODE, stranger, null, Map.of("kind", "PLAIN", "text", "fremd")), PAGE, other));
        var acrossPages = phone.push(edge(first, stranger));
        assertThat(acrossPages.getFirst().get("code")).isEqualTo("wiki.mindmap_element_gone");

        phone.push(SyncClient.deletion(NODE, second, null));
        var toDeleted = phone.push(edge(first, second));
        assertThat(toDeleted.getFirst().get("code")).isEqualTo("wiki.mindmap_element_gone");
    }

    @Test
    void anElementIsTurnedByWholeDegreesBelowAFullTurn() {
        UUID element = node(phone, "Meer");
        var turned = phone.push(onMap(NODE, element, null, Map.of("rotation", 90)));
        assertThat(turned.getFirst().get("status")).isEqualTo("applied");

        for (Object rotation : List.of(360, -1, 12.5)) {
            var result = phone.push(onMap(NODE, element, null, Map.of("rotation", rotation)));
            assertThat(result.getFirst().get("code")).as(rotation.toString()).isEqualTo("sync.invalid_field");
        }
    }

    @Test
    void aConnectionIsDrawnWithALineAndArrowHeadsNamedInCapitals() {
        UUID first = node(phone, "Meer");
        UUID second = node(phone, "Berge");
        Map<String, Object> styled = new HashMap<>(Map.of(
                "fromId", first.toString(), "toId", second.toString(), "line", "DASHED", "arrows", "END"));
        var drawn = phone.push(onMap(EDGE, UUID.randomUUID(), null, styled));
        assertThat(drawn.getFirst().get("status")).isEqualTo("applied");

        // A way a newer app knows is taken as well; anything else is not.
        for (var style : List.of(Map.of("line", "WAVY"), Map.of("arrows", "DIAMOND_END"))) {
            Map<String, Object> fields = new HashMap<>(Map.of("fromId", first.toString(), "toId", second.toString()));
            fields.putAll(style);
            var result = phone.push(onMap(EDGE, UUID.randomUUID(), null, fields));
            assertThat(result.getFirst().get("status")).as(style.toString()).isEqualTo("applied");
        }
        for (var style : List.of(Map.of("line", "dashed"), Map.of("arrows", "-->"))) {
            Map<String, Object> fields = new HashMap<>(Map.of("fromId", first.toString(), "toId", second.toString()));
            fields.putAll(style);
            var result = phone.push(onMap(EDGE, UUID.randomUUID(), null, fields));
            assertThat(result.getFirst().get("code")).as(style.toString()).isEqualTo("sync.invalid_field");
        }
    }

    @Test
    void elementsOnlyGoOnAMindMapThatIsNotArchived() {
        UUID text = page("Notizen", "PAGE");
        var onText = phone.push(SyncClient.withContainer(
                SyncClient.mutation(NODE, UUID.randomUUID(), null, Map.of("kind", "PLAIN")), PAGE, text));
        assertThat(onText.getFirst().get("code")).isEqualTo("wiki.not_a_mindmap");

        UUID element = node(phone, "Meer");
        phone.push(SyncClient.mutation(PAGE, map, null, Map.of("archivedAt", "2026-11-20T10:00:00Z")));
        var archived = phone.push(onMap(NODE, element, null, Map.of("text", "Strand")));
        assertThat(archived.getFirst().get("code")).isEqualTo("archive.read_only");
    }

    @Test
    void theMapFollowsItsPagesShare() {
        UUID element = node(phone, "Meer");
        assertThat(merged(bensTablet.pullAll(), element)).isEmpty();
        var unseen = bensTablet.push(onMap(NODE, UUID.randomUUID(), null, Map.of("kind", "PLAIN")));
        assertThat(unseen.getFirst().get("status")).isEqualTo("rejected");

        share("READ");
        assertThat(merged(bensTablet.pullSnapshot(50), element)).containsEntry("text", "Meer");
        var reader = bensTablet.push(onMap(NODE, UUID.randomUUID(), null, Map.of("kind", "PLAIN")));
        assertThat(reader.getFirst().get("code")).isEqualTo("access.denied");

        share("WRITE");
        UUID his = node(bensTablet, "Ski");
        var connected = bensTablet.push(edge(element, his));
        assertThat(connected.getFirst().get("status")).isEqualTo("applied");
        assertThat(merged(phone.pullAll(), his)).containsEntry("text", "Ski");
    }

    @Test
    void anElementTakesItsConnectionsAlong() {
        UUID first = node(phone, "Meer");
        UUID second = node(phone, "Berge");
        UUID connection = UUID.randomUUID();
        var labelled = phone.push(onMap(EDGE, connection, null, Map.of(
                "fromId", first.toString(), "toId", second.toString(), "text", "oder", "color", "RUST")));
        assertThat(labelled.getFirst().get("status")).isEqualTo("applied");
        assertThat(merged(laptop.pullAll(), connection)).containsEntry("text", "oder").containsEntry("color", "RUST");

        phone.push(SyncClient.deletion(NODE, second, null));

        assertThat(deleted(MINDMAP_EDGE, connection)).isTrue();
        assertThat(merged(laptop.pullAll(), connection)).containsEntry("op", "delete");
        // An edit made offline brings a connection back -- not one whose element is gone.
        var revived = laptop.push(onMap(EDGE, connection, null, Map.of("text", "und")));
        assertThat(revived.getFirst().get("code")).isEqualTo("wiki.mindmap_element_gone");
    }

    @Test
    void thePageTakesItsMapAlongAndBringsBackWhatWentWithIt() {
        UUID kept = node(phone, "Meer");
        UUID other = node(phone, "Berge");
        UUID earlier = node(phone, "Wüste");
        var connection = edge(kept, other);
        phone.push(connection);
        UUID connectionId = UUID.fromString(connection.get("entityId").toString());
        phone.push(SyncClient.deletion(NODE, earlier, null));

        phone.push(SyncClient.deletion(PAGE, map, null));
        assertThat(deleted(MINDMAP_NODE, kept)).isTrue();
        assertThat(deleted(MINDMAP_EDGE, connectionId)).isTrue();

        // Not in the trash on their own: hundreds of elements would bury the page.
        rest.get()
                .uri("/api/v1/trash")
                .headers(anna.auth())
                .exchange()
                .expectBody()
                .jsonPath("$.entries.length()")
                .isEqualTo(1);

        laptop.pullAll();
        rest.post()
                .uri("/api/v1/trash/" + PAGE + "/" + map + "/restore")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        assertThat(deleted(MINDMAP_NODE, kept)).isFalse();
        assertThat(deleted(MINDMAP_NODE, other)).isFalse();
        assertThat(deleted(MINDMAP_EDGE, connectionId)).isFalse();
        // Deleted on its own before the page went: it stays deleted.
        assertThat(deleted(MINDMAP_NODE, earlier)).isTrue();

        // And the devices get them back in full: they had only tombstones left.
        var back = laptop.pullAll();
        assertThat(merged(back, kept)).containsEntry("op", "upsert").containsEntry("text", "Meer");
        assertThat(merged(back, connectionId)).containsEntry("fromId", kept.toString());
    }

    @Test
    void aLinkOnTheMapIsOneFromThePageAndAWordOnItFindsThePage() {
        UUID target = page("Packliste", "PAGE");
        UUID element = UUID.randomUUID();
        phone.push(onMap(NODE, element, null, Map.of(
                "kind", "LINK", "target", "hiwiski://wiki_page/" + target)));
        node(phone, "Schnorchelausrüstung");
        // A member on the map is no link of the page.
        var member = phone.push(onMap(NODE, UUID.randomUUID(), null, Map.of(
                "kind", "MEMBER", "target", "hiwiski://member/" + UUID.randomUUID())));
        assertThat(member.getFirst().get("status")).isEqualTo("applied");
        FollowUps.await(db);

        Map<?, ?> links = rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + target)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((List<?>) links.get("incoming")).singleElement().satisfies(link -> {
            assertThat(((Map<?, ?>) link).get("itemType")).isEqualTo(PAGE);
            assertThat(((Map<?, ?>) link).get("title")).isEqualTo("Urlaub");
        });

        Map<?, ?> found = rest.get()
                .uri("/api/v1/search?q={q}", "Schnorchelausrüstung")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((List<?>) found.get("hits"))
                .anySatisfy(hit -> assertThat(((Map<?, ?>) hit).get("itemId")).isEqualTo(map.toString()));

        // Gone from the map, gone from the page's references.
        phone.push(SyncClient.deletion(NODE, element, null));
        FollowUps.await(db);
        Map<?, ?> after = rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + target)
                .headers(anna.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((List<?>) after.get("incoming")).isEmpty();
    }
}
