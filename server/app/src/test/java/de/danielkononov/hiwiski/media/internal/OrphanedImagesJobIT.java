package de.danielkononov.hiwiski.media.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;
import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.jooq.DSLContext;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.MultipartBodyBuilder;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * The weekly cleanup keeps the images a page's text shows — now or in one of its
 * revisions — and removes the ones nothing names.
 *
 * <p>It used to count only the recipe picture: every image placed in a page's text was
 * gone on Sunday night.
 */
@IntegrationTest
class OrphanedImagesJobIT {

    private static final String PAGE = "WIKI_PAGE";

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;
    @Autowired OrphanedImagesJob job;

    @Test
    void imagesInTheTextOrARevisionStayTheOthersGo() throws Exception {
        var anna = Family.setUp(rest);
        var device = new SyncClient(rest, anna);
        var page = UUID.randomUUID();
        device.push(SyncClient.mutation(PAGE, page, null, Map.of("title", "Holidays", "kind", "PAGE")));

        var shown = upload(anna, page);
        var removed = upload(anna, page);
        var neverPlaced = upload(anna, page);

        // Both in the text; then the second one taken out again.
        long version = version(device.push(SyncClient.mutation(
                PAGE, page, 1L, Map.of("content", image(shown) + "\n" + image(removed)))));
        waitForRevisions(page, 2);
        device.push(SyncClient.mutation(PAGE, page, version, Map.of("content", image(shown))));
        waitForRevisions(page, 3);

        // All three older than the grace period.
        db.update(MEDIA).set(MEDIA.CREATED_AT, OffsetDateTime.now().minusDays(2)).execute();
        job.run();

        var left = db.select(MEDIA.ID).from(MEDIA).fetch(MEDIA.ID);
        assertThat(left).contains(shown, removed).doesNotContain(neverPlaced);
    }

    @Test
    void anImageInATasksDescriptionStaysOneTakenOutGoes() throws Exception {
        var anna = Family.setUp(rest);
        var device = new SyncClient(rest, anna);
        var list = UUID.randomUUID();
        var task = UUID.randomUUID();
        device.push(SyncClient.mutation("TODO_LIST", list, null, Map.of("name", "Haus", "kind", "STANDARD")));
        device.push(SyncClient.withContainer(
                SyncClient.mutation("TODO", task, null, Map.of("title", "Regal bauen")), "TODO_LIST", list));

        var shown = upload(anna, "TODO", task);
        var dropped = upload(anna, "TODO", task);
        var onList = upload(anna, "TODO_LIST", list);
        device.push(SyncClient.mutation("TODO", task, 1L, Map.of("description", "Plan: " + image(shown))));
        device.push(SyncClient.mutation("TODO_LIST", list, 1L, Map.of("description", image(onList))));

        db.update(MEDIA).set(MEDIA.CREATED_AT, OffsetDateTime.now().minusDays(2)).execute();
        job.run();

        var left = db.select(MEDIA.ID).from(MEDIA).fetch(MEDIA.ID);
        assertThat(left).contains(shown, onList).doesNotContain(dropped);
    }

    private static String image(UUID id) {
        return "![](hiwiski-image:" + id + ")";
    }

    @SuppressWarnings("unchecked")
    private static long version(List<Map<String, Object>> results) {
        return ((Number) results.getFirst().get("version")).longValue();
    }

    /** Revisions are written after the commit, by a listener of their own. */
    private void waitForRevisions(UUID page, int count) throws InterruptedException {
        for (int i = 0; i < 100; i++) {
            if (db.fetchCount(WIKI_REVISION, WIKI_REVISION.PAGE_ID.eq(page)) >= count) {
                return;
            }
            Thread.sleep(50);
        }
        throw new AssertionError("no revision " + count + " for " + page);
    }

    @SuppressWarnings("unchecked")
    private UUID upload(Family.Session who, UUID page) throws IOException {
        return upload(who, PAGE, page);
    }

    @SuppressWarnings("unchecked")
    private UUID upload(Family.Session who, String ownerType, UUID owner) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(40, 30, BufferedImage.TYPE_INT_RGB), "png", out);
        var body = new MultipartBodyBuilder();
        body.part("ownerType", ownerType);
        body.part("ownerItemId", owner.toString());
        body.part("file", new ByteArrayResource(out.toByteArray()) {
                    @Override
                    public String getFilename() {
                        return "image.png";
                    }
                })
                .contentType(MediaType.IMAGE_PNG);
        var info = rest.post()
                .uri("/api/v1/images")
                .headers(who.auth())
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body.build())
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return UUID.fromString((String) info.get("id"));
    }
}
