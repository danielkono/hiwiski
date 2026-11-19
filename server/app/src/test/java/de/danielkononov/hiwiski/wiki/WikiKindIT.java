package de.danielkononov.hiwiski.wiki;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
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
 * A kind's fields live in the page's property map, and still go through sync each on
 * its own: their own conflict check, their own place in the log and the
 * snapshot, their values checked.
 */
@IntegrationTest
class WikiKindIT {

    private static final String PAGE = "WIKI_PAGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private SyncClient phone;
    private SyncClient laptop;

    @BeforeEach
    void twoDevices() {
        var first = Family.setUp(rest);
        var second = Family.login(rest, "anna", "geheim-genug", "Laptop");
        phone = new SyncClient(rest, first);
        laptop = new SyncClient(rest, second);
    }

    private static long version(Map<String, Object> result) {
        return ((Number) result.get("version")).longValue();
    }

    private UUID recipe(Map<String, Object> fields) {
        UUID id = UUID.randomUUID();
        var all = new java.util.LinkedHashMap<String, Object>(Map.of("title", "Plov", "kind", "RECIPE"));
        all.putAll(fields);
        phone.push(SyncClient.mutation(PAGE, id, null, all));
        return id;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> merged(List<Map<String, Object>> changes, UUID id) {
        Map<String, Object> state = new java.util.LinkedHashMap<>();
        changes.stream()
                .filter(change -> id.toString().equals(change.get("entityId")))
                .forEach(change -> state.putAll((Map<String, Object>) change.get("fields")));
        return state;
    }

    @Test
    void aRecipesFieldsArriveAndAreStoredAsProperties() {
        UUID id = recipe(Map.of(
                "servings", 6,
                "ingredients", List.of(Map.of("label", "Reis", "amount", 500, "unit", "g")),
                "sourceUrl", "https://example.org/plov"));

        var recipe = merged(laptop.pullAll(), id);
        assertThat(recipe).containsEntry("servings", 6).containsEntry("sourceUrl", "https://example.org/plov");
        assertThat((List<?>) recipe.get("ingredients")).hasSize(1);
        // A recipe gets its number from its own range.
        String key = db.select(WIKI_PAGE.ENTITY_KEY).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(id)).fetchOne(
                WIKI_PAGE.ENTITY_KEY);
        assertThat(key).startsWith("REC-");

        var snapshot = merged(new SyncClient(rest, Family.login(rest, "anna", "geheim-genug", "Tablet"))
                .pullSnapshot(50), id);
        assertThat(snapshot).containsEntry("servings", 6);
    }

    @Test
    void twoPropertiesChangedAtOnceBothStayOneChangedTwiceConflicts() {
        UUID id = recipe(Map.of("servings", 4, "sourceUrl", "https://a.example"));
        long known = version(phone.push(
                SyncClient.mutation(PAGE, id, null, Map.of("title", "Plov")))
                .getFirst());
        laptop.pullAll();

        var fromLaptop = laptop.push(SyncClient.mutation(PAGE, id, known, Map.of("servings", 8)));
        assertThat(fromLaptop.getFirst().get("status")).isEqualTo("applied");

        var fromPhone = phone.push(
                // Another property: goes through on the old state.
                SyncClient.mutation(PAGE, id, known, Map.of("sourceUrl", "https://b.example")),
                // The same property: a conflict, with the server's value.
                SyncClient.mutation(PAGE, id, known, Map.of("servings", 2)));
        assertThat(fromPhone.get(0).get("status")).isEqualTo("applied");
        assertThat(fromPhone.get(1).get("status")).isEqualTo("conflict");
        assertThat(List.copyOf((List<?>) fromPhone.get(1).get("conflictFields"))).isEqualTo(List.of("servings"));
        assertThat(((Map<?, ?>) fromPhone.get(1).get("serverFields")).get("servings")).isEqualTo(8);

        laptop.setLastSeq(0);
        var recipe = merged(laptop.pullAll(), id);
        assertThat(recipe).containsEntry("servings", 8).containsEntry("sourceUrl", "https://b.example");
    }

    @Test
    void aValueThatDoesNotFitIsRefused() {
        UUID id = recipe(Map.of());
        var result = phone.push(SyncClient.mutation(PAGE, id, null, Map.of("servings", "viele")));
        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
    }
}
