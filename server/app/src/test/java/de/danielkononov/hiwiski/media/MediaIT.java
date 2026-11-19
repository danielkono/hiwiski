package de.danielkononov.hiwiski.media;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Map;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.MultipartBodyBuilder;
import org.springframework.test.web.servlet.client.RestTestClient;

/** Media storage: always with an owner item, visible along with the owner. */
@IntegrationTest
class MediaIT {

    @Autowired RestTestClient rest;

    private Family.Session anna;
    private Family.Session ben;
    private UUID recipe;

    @BeforeEach
    void family() {
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
        recipe = UUID.randomUUID();
        new SyncClient(rest, anna)
                .push(SyncClient.mutation("WIKI_PAGE", recipe, null, Map.of("title", "Kuerbissuppe", "kind", "RECIPE")));
    }

    @Test
    @SuppressWarnings("unchecked")
    void uploadServeAndPreview() throws IOException {
        var info = upload(anna, "WIKI_PAGE", recipe, png(1600, 800))
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        assertThat(info).containsEntry("contentType", "image/png").containsEntry("width", 1600);
        var id = info.get("id");

        var original = rest.get()
                .uri("/api/v1/images/" + id)
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(byte[].class)
                .returnResult()
                .getResponseBody();
        assertThat(ImageIO.read(new ByteArrayInputStream(original)).getWidth()).isEqualTo(1600);

        var preview = rest.get()
                .uri("/api/v1/images/" + id + "/preview")
                .headers(anna.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(byte[].class)
                .returnResult()
                .getResponseBody();
        var small = ImageIO.read(new ByteArrayInputStream(preview));
        assertThat(small.getWidth()).isEqualTo(640);
        assertThat(small.getHeight()).isEqualTo(320);
    }

    @Test
    void noOwnerNoImage() throws IOException {
        // An owner that does not exist is the same as none to the server.
        upload(anna, "WIKI_PAGE", UUID.randomUUID(), png(10, 10)).expectStatus().isNotFound();
        // A type that carries no images: a calendar holds no text with pictures.
        upload(anna, "CALENDAR", recipe, png(10, 10)).expectStatus().isBadRequest();
    }

    @Test
    @SuppressWarnings("unchecked")
    void theImageInheritsTheShareOfItsOwner() throws IOException {
        var id = upload(anna, "WIKI_PAGE", recipe, png(20, 20))
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("id");

        // The page belongs to Anna alone: Ben sees neither it nor its image, and he may
        // not attach one either.
        rest.get().uri("/api/v1/images/" + id).headers(ben.auth()).exchange().expectStatus().isNotFound();
        upload(ben, "WIKI_PAGE", recipe, png(20, 20)).expectStatus().isNotFound();

        rest.put()
                .uri("/api/v1/items/WIKI_PAGE/" + recipe + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", java.util.List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", ben.memberId().toString(), "level", "READ"))))
                .exchange()
                .expectStatus()
                .is2xxSuccessful();

        rest.get().uri("/api/v1/images/" + id).headers(ben.auth()).exchange().expectStatus().isOk();
        upload(ben, "WIKI_PAGE", recipe, png(20, 20)).expectStatus().isForbidden();
    }

    /**
     * An image belongs to the page it was uploaded for. Set on another page, the
     * weekly cleanup took it away after a day, and that page's readers who could not see
     * the first page got a 404.
     */
    @Test
    @SuppressWarnings("unchecked")
    void aPageUsesOnlyImagesUploadedForIt() throws IOException {
        var device = new SyncClient(rest, anna);
        var id = upload(anna, "WIKI_PAGE", recipe, png(20, 20))
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("id");
        UUID other = UUID.randomUUID();
        device.push(SyncClient.mutation("WIKI_PAGE", other, null, Map.of("title", "Kopie", "kind", "RECIPE")));

        var foreign = device.push(SyncClient.mutation("WIKI_PAGE", UUID.randomUUID(), null, Map.of(
                "title", "Noch eine", "kind", "RECIPE", "imageId", id)));
        var own = device.push(SyncClient.mutation("WIKI_PAGE", recipe, null, Map.of("imageId", id)));

        assertThat(foreign.getFirst().get("status")).isEqualTo("rejected");
        assertThat(foreign.getFirst().get("code")).isEqualTo("wiki.image_foreign");
        assertThat(own.getFirst().get("status")).isNotEqualTo("rejected");
    }

    /** One's own picture: uploaded with oneself as carrier, set on the profile, seen by all. */
    @Test
    @SuppressWarnings("unchecked")
    void aMemberSetsTheirOwnPictureAndTheFamilySeesIt() throws IOException {
        var id = upload(ben, "MEMBER", ben.memberId(), png(300, 300))
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody()
                .get("id");

        rest.patch()
                .uri("/api/v1/members/" + ben.memberId())
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("avatarImageId", id))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.avatarImageId").isEqualTo(id);

        // Anna shares nothing with Ben, and still sees his picture -- like his name.
        rest.get().uri("/api/v1/images/" + id + "/preview").headers(anna.auth()).exchange().expectStatus().isOk();

        // Nobody hangs a picture on someone else's profile, nor someone else's upload on theirs.
        upload(anna, "MEMBER", ben.memberId(), png(10, 10)).expectStatus().isForbidden();
        rest.patch()
                .uri("/api/v1/members/" + anna.memberId())
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("avatarImageId", id))
                .exchange()
                .expectStatus()
                .isBadRequest();

        rest.patch()
                .uri("/api/v1/members/" + ben.memberId())
                .headers(ben.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("removeAvatar", true))
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody()
                .jsonPath("$.avatarImageId").doesNotExist();
    }

    @Test
    void noImageNoUpload() {
        upload(anna, "WIKI_PAGE", recipe, "not an image".getBytes()).expectStatus().isBadRequest();
    }

    /**
     * An image added without a server keeps its id: the carrier points to
     * it already. The same upload twice -- the answer lost on the way -- is one image.
     */
    @Test
    void anImageKeepsTheIdTheAppBringsAndASecondUploadIsTheSame() throws IOException {
        var id = UUID.randomUUID();
        for (int attempt = 0; attempt < 2; attempt++) {
            upload(anna, "WIKI_PAGE", recipe, id, png(40, 20))
                    .expectStatus()
                    .isCreated()
                    .expectBody()
                    .jsonPath("$.id")
                    .isEqualTo(id.toString())
                    .jsonPath("$.width")
                    .isEqualTo(40);
        }
        rest.get().uri("/api/v1/images/" + id).headers(anna.auth()).exchange().expectStatus().isOk();
    }

    /** An id taken by someone else's image is refused, never overwritten. */
    @Test
    void anIdTakenByAnotherImageIsRefused() throws IOException {
        var id = UUID.randomUUID();
        upload(anna, "WIKI_PAGE", recipe, id, png(40, 20)).expectStatus().isCreated();
        var page = UUID.randomUUID();
        new SyncClient(rest, ben).push(SyncClient.mutation("WIKI_PAGE", page, null, Map.of("title", "Bens Seite")));

        upload(ben, "WIKI_PAGE", page, id, png(10, 10))
                .expectStatus()
                .isEqualTo(409)
                .expectBody()
                .jsonPath("$.code")
                .isEqualTo("media.id_taken");
    }

    /**
     * The same new id from several uploads at once: one row wins, the same upload again
     * is that row, someone else's is refused -- never a 500.
     */
    @Test
    void uploadsOfOneNewIdAtOnceAreOneImageOrRefused() throws Exception {
        var page = UUID.randomUUID();
        new SyncClient(rest, ben).push(SyncClient.mutation("WIKI_PAGE", page, null, Map.of("title", "Bens Seite")));
        for (int round = 0; round < 5; round++) {
            var id = UUID.randomUUID();
            var bytes = png(30 + round, 20);
            var statuses = new java.util.concurrent.ConcurrentLinkedQueue<Integer>();
            try (var threads = java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()) {
                var start = new java.util.concurrent.CountDownLatch(1);
                for (int i = 0; i < 6; i++) {
                    var who = i % 3 == 2 ? ben : anna;
                    var carrier = who == ben ? page : recipe;
                    threads.submit(() -> {
                        start.await();
                        statuses.add(upload(who, "WIKI_PAGE", carrier, id, bytes)
                                .returnResult(String.class)
                                .getStatus()
                                .value());
                        return null;
                    });
                }
                start.countDown();
            }
            assertThat(statuses).hasSize(6).allMatch(status -> status == 201 || status == 409);
        }
    }

    private RestTestClient.ResponseSpec upload(Family.Session who, String ownerType, UUID ownerItemId, byte[] bytes) {
        return upload(who, ownerType, ownerItemId, null, bytes);
    }

    private RestTestClient.ResponseSpec upload(
            Family.Session who, String ownerType, UUID ownerItemId, UUID id, byte[] bytes) {
        var body = new MultipartBodyBuilder();
        body.part("ownerType", ownerType);
        body.part("ownerItemId", ownerItemId.toString());
        if (id != null) {
            body.part("id", id.toString());
        }
        body.part("file", new ByteArrayResource(bytes) {
                    @Override
                    public String getFilename() {
                        return "image.png";
                    }
                })
                .contentType(MediaType.IMAGE_PNG);
        return rest.post()
                .uri("/api/v1/images")
                .headers(who.auth())
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body.build())
                .exchange();
    }

    private static byte[] png(int width, int height) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "png", out);
        return out.toByteArray();
    }
}
