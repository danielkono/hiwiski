package de.danielkononov.hiwiski.wiki;

import static de.danielkononov.hiwiski.db.generated.Tables.EFFECTIVE_ACCESS;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.FollowUps;
import de.danielkononov.hiwiski.support.SyncClient;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.jooq.DSLContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The wiki's acceptance case, first part.
 *
 * <p>"Create a page three levels deep, share a subpage on its own, move the branch —
 * <strong>the shares are right afterwards.</strong>"
 *
 * <p>This is the case that shows whether inheritance is really recursive: an own share has
 * to survive the move, an inherited one has to realign.
 */
@IntegrationTest
class WikiTreeIT {

    private static final String PAGE = "WIKI_PAGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;
    private SyncClient annasDevice;
    private SyncClient bensDevice;

    @BeforeEach
    void familyWithTwoMembers() {
        anna = Family.setUp(rest);
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24"))
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        var signedIn = rest.post()
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
        ben = Family.toSession(signedIn);

        annasDevice = new SyncClient(rest, anna);
        bensDevice = new SyncClient(rest, ben);
    }

    private UUID page(String title, UUID parent) {
        UUID id = UUID.randomUUID();
        var fields = Map.<String, Object>of("title", title, "kind", "PAGE", "content", "");
        annasDevice.push(
                parent == null
                        ? SyncClient.mutation(PAGE, id, null, fields)
                        : SyncClient.withContainer(SyncClient.mutation(PAGE, id, null, fields), PAGE, parent));
        return id;
    }

    private void share(UUID pageId, String level) {
        rest.put()
                .uri("/api/v1/items/" + PAGE + "/" + pageId + "/shares")
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

    private boolean benSees(UUID pageId) {
        return db.fetchExists(db.selectFrom(EFFECTIVE_ACCESS)
                .where(EFFECTIVE_ACCESS.MEMBER_ID.eq(ben.memberId()))
                .and(EFFECTIVE_ACCESS.ITEM_TYPE.eq(PAGE))
                .and(EFFECTIVE_ACCESS.ITEM_ID.eq(pageId)));
    }

    @Test
    void threeLevelsDeepAndTheBranchMoves() {
        // Haus > Technik > Router. Arbitrary depth -- a page without a parent
        // is what used to be a section.
        UUID house = page("Haus", null);
        UUID tech = page("Technik", house);
        UUID router = page("Router", tech);

        assertThat(db.fetchCount(WIKI_PAGE, WIKI_PAGE.DELETED_AT.isNull())).isEqualTo(3);
        assertThat(benSees(house)).isFalse();

        // Share a subpage on its own.
        share(tech, "READ");
        assertThat(benSees(tech)).describedAs("the shared page").isTrue();
        assertThat(benSees(router)).describedAs("and everything below it -- inherited").isTrue();
        assertThat(benSees(house)).describedAs("but not upwards").isFalse();

        // Move the branch: Technik now hangs off a second root.
        UUID garden = page("Garten", null);
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(tech))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.withContainer(
                SyncClient.mutation(PAGE, tech, version, Map.of("parentId", garden.toString())),
                PAGE,
                garden));

        assertThat(db.select(WIKI_PAGE.PARENT_ID)
                        .from(WIKI_PAGE)
                        .where(WIKI_PAGE.ID.eq(tech))
                        .fetchOne(WIKI_PAGE.PARENT_ID))
                .isEqualTo(garden);

        // **The shares are right afterwards.** The own share on "Technik" survives the
        // move, "Router" still inherits it, and "Garten" stays out of it.
        assertThat(benSees(tech)).describedAs("the own share survives").isTrue();
        assertThat(benSees(router)).describedAs("the inheritance moves along").isTrue();
        assertThat(benSees(garden)).describedAs("the new parent stays out of it").isFalse();
    }

    @Test
    void aDeletedBranchTakesEverythingBelowItWithIt() {
        UUID house = page("Haus", null);
        UUID tech = page("Technik", house);
        UUID router = page("Router", tech);

        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(house))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.deletion(PAGE, house, version));

        // "What goes along when deleting has to be enumerated"
        // -- recursively, that is, otherwise "Router" would
        // remain and be reachable from nowhere.
        assertThat(db.fetchCount(WIKI_PAGE, WIKI_PAGE.DELETED_AT.isNull())).isZero();
        assertThat(db.fetchExists(db.selectFrom(WIKI_PAGE)
                        .where(WIKI_PAGE.ID.eq(router))
                        .and(WIKI_PAGE.DELETED_AT.isNotNull())))
                .isTrue();
    }

    @Test
    void everySaveCreatesARevision() {
        UUID pageId = page("Router", null);
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .fetchOne(WIKI_PAGE.VERSION);

        long saved = ((Number) annasDevice.push(
                                SyncClient.mutation(PAGE, pageId, version, Map.of("content", "The IP is 192.168.1.1.")))
                        .getFirst()
                        .get("version"))
                .longValue();

        FollowUps.await(db);

        var revisions = db.selectFrom(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                .orderBy(WIKI_REVISION.SEQ.asc())
                .fetch();

        assertThat(revisions).describedAs("creating and changing are two revisions").hasSize(2);
        assertThat(revisions.getLast().getContent()).contains("192.168.1.1");
        assertThat(revisions.getLast().getKind()).isEqualTo("SAVE");
        // The save it came from -- the history row that opens this version.
        assertThat(revisions.getLast().getChangeSeq()).isEqualTo(saved);
        assertThat(revisions.getFirst().getChangeSeq()).describedAs("the creation").isEqualTo(version);
    }

    /**
     * Two saves by two people in a row: each revision holds that save's text under that
     * person's name -- even when the first one's revision is written after the second
     * save, which it used to store as Anna's with Ben's text.
     */
    @Test
    void eachRevisionHoldsItsOwnSaveAndAuthor() {
        UUID pageId = page("Router", null);
        share(pageId, "WRITE");
        long version = db.select(WIKI_PAGE.VERSION).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(pageId)).fetchOne(WIKI_PAGE.VERSION);
        FollowUps.await(db);

        long annas = ((Number) annasDevice.push(
                                SyncClient.mutation(PAGE, pageId, version, Map.of("content", "Annas Text")))
                        .getFirst()
                        .get("version"))
                .longValue();
        bensDevice.push(SyncClient.mutation(PAGE, pageId, annas, Map.of("content", "Bens Text")));
        FollowUps.await(db);

        var saves = db.selectFrom(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                .and(WIKI_REVISION.KIND.eq("SAVE"))
                .orderBy(WIKI_REVISION.SEQ.asc())
                .fetch();
        assertThat(saves)
                .extracting(revision -> revision.getContent(), revision -> revision.getAuthorId())
                .contains(
                        org.assertj.core.groups.Tuple.tuple("Annas Text", anna.memberId()),
                        org.assertj.core.groups.Tuple.tuple("Bens Text", ben.memberId()));
    }

    /**
     * The wiki text special case: both edit the same version, Ben saves
     * first. Anna's text loses — and afterwards appears in the history as a
     * {@code CONFLICT} revision instead of silently disappearing.
     */
    @Test
    void theLosingVersionIsStoredAsAConflictRevision() {
        UUID pageId = page("Router", null);
        share(pageId, "WRITE");
        long created = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.mutation(PAGE, pageId, created, Map.of("content", "Starting point")));
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .fetchOne(WIKI_PAGE.VERSION);

        bensDevice.push(SyncClient.mutation(PAGE, pageId, version, Map.of("content", "Ben's version")));
        var results = annasDevice.push(SyncClient.mutation(
                PAGE, pageId, version, Map.of("title", "Router (new)", "content", "Anna's version")));

        assertThat(results.getFirst().get("status")).isEqualTo("conflict");
        assertThat(List.copyOf((List<?>) results.getFirst().get("conflictFields"))).isEqualTo(List.of("content"));
        // What both started from -- the conflict view shows it next to the two versions.
        assertThat(((Map<?, ?>) results.getFirst().get("baseFields")).get("content")).isEqualTo("Starting point");

        FollowUps.await(db);

        var page = db.selectFrom(WIKI_PAGE).where(WIKI_PAGE.ID.eq(pageId)).fetchOne();
        assertThat(page.getContent()).describedAs("the server state wins").isEqualTo("Ben's version");
        assertThat(page.getTitle()).describedAs("the other field goes through").isEqualTo("Router (new)");

        var conflict = db.selectFrom(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                .and(WIKI_REVISION.KIND.eq("CONFLICT"))
                .fetch();
        assertThat(conflict).hasSize(1);
        assertThat(conflict.getFirst().getContent()).isEqualTo("Anna's version");
        assertThat(conflict.getFirst().getTitle()).isEqualTo("Router (new)");
        assertThat(conflict.getFirst().getAuthorId()).isEqualTo(anna.memberId());
        assertThat(conflict.getFirst().getChangeSeq())
                .describedAs("the save that lost was never written")
                .isNull();
    }

    @Test
    void aSaveWithoutChangesCreatesNoRevision() {
        UUID pageId = page("Router", null);
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(pageId))
                .fetchOne(WIKI_PAGE.VERSION);

        // The editor saves every few seconds. A history with a hundred
        // identical entries is not a history.
        annasDevice.push(SyncClient.mutation(PAGE, pageId, version, Map.of("title", "Router")));

        FollowUps.await(db);
        assertThat(db.fetchCount(WIKI_REVISION, WIKI_REVISION.PAGE_ID.eq(pageId))).isEqualTo(1);
    }

    @Test
    void linksAreParsedFromTheTextAndShownInBothDirections() {
        UUID target = page("Router", null);
        String key = db.select(WIKI_PAGE.ENTITY_KEY)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(target))
                .fetchOne(WIKI_PAGE.ENTITY_KEY);
        assertThat(key).describedAs("a page gets its number on the first sync").isNotNull();

        UUID source = page("Internet", null);
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(source))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.mutation(
                PAGE, source, version, Map.of("content", "Credentials are in #" + key + ".")));

        FollowUps.await(db);

        var outgoing = rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + source)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var links = (List<Map<String, Object>>) outgoing.get("outgoing");
        assertThat(links).describedAs("parsed from the text, not maintained by hand").hasSize(1);
        // With the CURRENT title, not the text that applied when writing.
        assertThat(links.getFirst().get("title")).isEqualTo("Router");

        // And in the other direction.
        var incoming = rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + target)
                .headers(anna.auth())
                .exchange()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        @SuppressWarnings("unchecked")
        var back = (List<Map<String, Object>>) incoming.get("incoming");
        assertThat(back).hasSize(1);
        assertThat(back.getFirst().get("title")).isEqualTo("Internet");
    }

    @Test
    void whatTheReaderMayNotSeeIsLeftOutEntirely() {
        UUID secret = page("Router", null);
        String key = db.select(WIKI_PAGE.ENTITY_KEY)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(secret))
                .fetchOne(WIKI_PAGE.ENTITY_KEY);

        UUID open = page("Internet", null);
        long version = db.select(WIKI_PAGE.VERSION)
                .from(WIKI_PAGE)
                .where(WIKI_PAGE.ID.eq(open))
                .fetchOne(WIKI_PAGE.VERSION);
        annasDevice.push(SyncClient.mutation(PAGE, open, version, Map.of("content", "See #" + key + ".")));
        share(open, "READ");

        FollowUps.await(db);

        var seen = rest.get()
                .uri("/api/v1/links/" + PAGE + "/" + open)
                .headers(ben.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();

        @SuppressWarnings("unchecked")
        var links = (List<Map<String, Object>>) seen.get("outgoing");
        // Left out entirely instead of "access denied": existence is information too.
        assertThat(links).isEmpty();
        assertThat(bensDevice.pullAll()).noneSatisfy(entry ->
                assertThat(entry.get("entityId")).isEqualTo(secret.toString()));
    }

    private UUID parentOf(UUID pageId) {
        return db.select(WIKI_PAGE.PARENT_ID).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(pageId)).fetchOne(WIKI_PAGE.PARENT_ID);
    }

    /**
     * A move hands the page to the target's audience -- whoever may write the page still
     * needs write access to where it goes.
     */
    @Test
    void aPageDoesNotMoveIntoAPageItsAuthorMayNotWrite() {
        UUID private_ = page("Privat", null);
        UUID shared = page("Geteilt", null);
        share(shared, "READ");
        UUID bens = UUID.randomUUID();
        bensDevice.push(SyncClient.mutation(PAGE, bens, null, Map.of("title", "Bens", "kind", "PAGE", "content", "")));
        long version = db.select(WIKI_PAGE.VERSION).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(bens)).fetchOne(WIKI_PAGE.VERSION);

        for (UUID target : List.of(private_, shared)) {
            var result = bensDevice.push(
                    SyncClient.mutation(PAGE, bens, version, Map.of("parentId", target.toString())));

            assertThat(result.getFirst().get("status")).isEqualTo("rejected");
            assertThat(result.getFirst().get("code")).isEqualTo("access.denied");
            assertThat(parentOf(bens)).isNull();
        }
    }

    /** The parent a new page names in its fields is the one checked, not the envelope's. */
    @Test
    void aNewPageCannotClaimOneParentAndNameAnother() {
        UUID private_ = page("Privat", null);
        UUID bens = UUID.randomUUID();
        bensDevice.push(SyncClient.mutation(PAGE, bens, null, Map.of("title", "Bens", "kind", "PAGE", "content", "")));

        UUID sneaked = UUID.randomUUID();
        var result = bensDevice.push(SyncClient.withContainer(
                SyncClient.mutation(
                        PAGE,
                        sneaked,
                        null,
                        Map.of("title", "Unterschoben", "kind", "PAGE", "content", "", "parentId", private_.toString())),
                PAGE,
                bens));

        assertThat(result.getFirst().get("status")).isEqualTo("rejected");
        assertThat(db.fetchExists(db.selectFrom(WIKI_PAGE).where(WIKI_PAGE.ID.eq(sneaked)))).isFalse();
    }

    /** Write access to the target is enough: the owner of a shared page moves in. */
    @Test
    void aPageMovesIntoAPageItsAuthorMayWrite() {
        UUID shared = page("Geteilt", null);
        share(shared, "WRITE");
        UUID bens = UUID.randomUUID();
        bensDevice.push(SyncClient.mutation(PAGE, bens, null, Map.of("title", "Bens", "kind", "PAGE", "content", "")));
        long version = db.select(WIKI_PAGE.VERSION).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(bens)).fetchOne(WIKI_PAGE.VERSION);

        var result = bensDevice.push(SyncClient.mutation(PAGE, bens, version, Map.of("parentId", shared.toString())));

        assertThat(result.getFirst().get("status")).isEqualTo("applied");
        assertThat(parentOf(bens)).isEqualTo(shared);
    }

    /** A page does not go under itself or below its own subpages. */
    @Test
    void aPageCannotBecomeItsOwnAncestor() {
        UUID house = page("Haus", null);
        UUID tech = page("Technik", house);
        UUID router = page("Router", tech);
        long version = db.select(WIKI_PAGE.VERSION).from(WIKI_PAGE).where(WIKI_PAGE.ID.eq(house)).fetchOne(WIKI_PAGE.VERSION);

        for (UUID target : List.of(house, router)) {
            var result = annasDevice.push(SyncClient.mutation(PAGE, house, version, Map.of("parentId", target.toString())));
            assertThat(result.getFirst().get("code")).isEqualTo("wiki.move_cycle");
        }
        assertThat(parentOf(house)).isNull();
    }
}
