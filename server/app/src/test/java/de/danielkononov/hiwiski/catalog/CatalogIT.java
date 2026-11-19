package de.danielkononov.hiwiski.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/** The shopping list's categories belong to the family. */
@IntegrationTest
class CatalogIT {

    @Autowired RestTestClient rest;

    @Test
    void theCatalogStartsInTheLanguageOfTheSetup() {
        var session = setUp("de-AT");

        var quark = product(session, "Quark");
        assertThat(quark.get("aisleId")).isEqualTo(aisleId(session, "dairy_eggs"));
        assertThat(product(session, "Petersilie").get("defaultUnit")).isEqualTo("Bund");
        assertThat(products(session, "Milk")).isEmpty();
    }

    @Test
    void anUnknownLanguageGetsTheEnglishCatalog() {
        var session = setUp("pl");

        assertThat(product(session, "Milk").get("aisleId")).isEqualTo(aisleId(session, "dairy_eggs"));
        assertThat(products(session, "Quark")).isEmpty();
    }

    @Test
    void theBuiltInCategoriesComeInTheirDefaultOrder() {
        var session = setUp("en");

        var keys = aisles(session).stream().map(aisle -> aisle.get("key")).toList();
        assertThat(keys).startsWith("produce", "bakery").endsWith("household", "pet").hasSize(15);
    }

    @Test
    void assigningMovesTheProductWithExactlyThatNameOrCreatesIt() {
        var session = setUp("de");
        var frozen = aisleId(session, "frozen");

        assign(session, "kürbis", frozen);
        assertThat(product(session, "Kürbis").get("aisleId")).isEqualTo(frozen);
        // "Hokkaido-Kürbis" is a product of its own and stays where it was.
        assertThat(product(session, "Hokkaido-Kürbis").get("aisleId")).isEqualTo(aisleId(session, "produce"));

        assign(session, "Sojasoße", aisleId(session, "spices_condiments"));
        assertThat(product(session, "Sojasoße").get("aisleId")).isEqualTo(aisleId(session, "spices_condiments"));

        assign(session, "Sojasoße", null);
        assertThat(product(session, "Sojasoße").get("aisleId")).isNull();
    }

    /**
     * A name the JVM and the database lowercase differently: read back with Java's
     * lowercasing, the product was not found and the request failed with a 500.
     */
    @Test
    void aProductWithATurkishCapitalIIsAssigned() {
        var session = setUp("de");
        var produce = aisleId(session, "produce");

        assign(session, "İzmir-Feigen", produce);

        assertThat(product(session, "İzmir-Feigen").get("aisleId")).isEqualTo(produce);
    }

    /** Two devices creating the same category at once: one gets it, the other a 409. */
    @Test
    void twoCategoriesOfOneNameAtOnceAreAConflictNotAnError() throws Exception {
        var session = setUp("de");
        var start = new java.util.concurrent.CountDownLatch(1);
        var pool = java.util.concurrent.Executors.newFixedThreadPool(2);
        try {
            var runs = java.util.stream.IntStream.range(0, 2)
                    .mapToObj(i -> pool.submit(() -> {
                        start.await();
                        return rest.post()
                                .uri("/api/v1/catalog/aisles")
                                .headers(session.auth())
                                .contentType(MediaType.APPLICATION_JSON)
                                .body(Map.of("name", "Asia-Laden"))
                                .exchange()
                                .returnResult(Void.class)
                                .getStatus()
                                .value();
                    }))
                    .toList();
            start.countDown();
            var statuses = new java.util.ArrayList<Integer>();
            for (var run : runs) {
                statuses.add(run.get());
            }
            assertThat(statuses).containsExactlyInAnyOrder(201, 409);
        } finally {
            pool.shutdown();
        }
    }

    @Test
    void anOwnCategoryIsAppendedRenamedAndDeletedWithoutTakingItsProducts() {
        var session = setUp("de");

        var created = rest.post()
                .uri("/api/v1/catalog/aisles")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "Asia-Laden"))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        String id = (String) created.get("id");
        assertThat(created.get("position")).isEqualTo(15);

        // Two of the same name could not be told apart in the picker.
        rest.post()
                .uri("/api/v1/catalog/aisles")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "asia-laden"))
                .exchange()
                .expectStatus()
                .isEqualTo(409)
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("catalog.aisle_name_taken");

        rest.patch()
                .uri("/api/v1/catalog/aisles/" + id)
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "Asia-Markt"))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.name")
                .isEqualTo("Asia-Markt");

        assign(session, "Sojasoße", id);

        rest.delete()
                .uri("/api/v1/catalog/aisles/" + id)
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isNoContent();

        // The product stays, without a category: "Other".
        assertThat(product(session, "Sojasoße").get("aisleId")).isNull();
    }

    @Test
    void aBuiltInCategoryIsOnlyHiddenNeverRenamedOrDeleted() {
        var session = setUp("de");
        var baby = aisleId(session, "baby");

        rest.patch()
                .uri("/api/v1/catalog/aisles/" + baby)
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("name", "Kinder"))
                .exchange()
                .expectStatus()
                .isBadRequest()
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("catalog.aisle_builtin");

        rest.delete()
                .uri("/api/v1/catalog/aisles/" + baby)
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isBadRequest();

        rest.patch()
                .uri("/api/v1/catalog/aisles/" + baby)
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("hidden", true))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.hidden")
                .isEqualTo(true);
    }

    @Test
    void reorderingKeepsCategoriesTheRequestDidNotName() {
        var session = setUp("de");
        var frozen = aisleId(session, "frozen");
        var pet = aisleId(session, "pet");

        var result = rest.put()
                .uri("/api/v1/catalog/aisles/order")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("ids", List.of(pet, frozen)))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var keys = ((List<Map<String, Object>>) result.get("aisles")).stream()
                .map(aisle -> aisle.get("key"))
                .toList();
        assertThat(keys).hasSize(15).startsWith("pet", "frozen", "produce", "bakery");
        assertThat(aisles(session).stream().map(aisle -> aisle.get("key")).toList()).isEqualTo(keys);
    }

    // --- helpers -------------------------------------------------------------------

    private Family.Session setUp(String language) {
        var body = rest.post()
                .uri("/api/v1/setup")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "setupCode", Family.SETUP_CODE,
                        "backupPassword", Family.BACKUP_PASSWORD,
                        "familyName", "Familie Probe",
                        "timezone", "Europe/Berlin",
                        "admin", Map.of("displayName", "Anna", "username", "anna", "password", "geheim-genug"),
                        "device", Map.of("deviceName", "Annas iPhone", "platform", "IOS"),
                        "language", language))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(body);
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> aisles(Family.Session session) {
        var body = rest.get()
                .uri("/api/v1/catalog/aisles")
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return (List<Map<String, Object>>) body.get("aisles");
    }

    private Object aisleId(Family.Session session, String key) {
        return aisles(session).stream()
                .filter(aisle -> key.equals(aisle.get("key")))
                .findFirst()
                .orElseThrow()
                .get("id");
    }

    /** "_" is what was typed: it does not stand for any one letter. */
    @Test
    @SuppressWarnings("unchecked")
    void suggestionsTakeWildcardsAsText() {
        var session = Family.setUp(rest);
        var body = rest.get()
                .uri(builder -> builder.path("/api/v1/catalog/products").queryParam("query", "_").build())
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat((List<Object>) body.get("products")).isEmpty();
    }

    @SuppressWarnings("unchecked")
    private List<Map<String, Object>> products(Family.Session session, String query) {
        var body = rest.get()
                .uri(builder -> builder.path("/api/v1/catalog/products").queryParam("query", query).build())
                .headers(session.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return new ArrayList<>((List<Map<String, Object>>) body.get("products")).stream()
                .filter(product -> query.equalsIgnoreCase((String) product.get("name")))
                .toList();
    }

    private Map<String, Object> product(Family.Session session, String name) {
        var found = products(session, name);
        assertThat(found).as(name).hasSize(1);
        return found.getFirst();
    }

    private void assign(Family.Session session, String name, Object aisleId) {
        var body = new java.util.HashMap<String, Object>();
        body.put("name", name);
        body.put("aisleId", aisleId);
        rest.put()
                .uri("/api/v1/catalog/products/aisle")
                .headers(session.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .exchange()
                .expectStatus()
                .isOk();
    }
}
