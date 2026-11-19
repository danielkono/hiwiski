package de.danielkononov.hiwiski.security;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.support.Family;
import de.danielkononov.hiwiski.support.IntegrationTest;
import de.danielkononov.hiwiski.support.SyncClient;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.imageio.ImageIO;
import org.jooq.DSLContext;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.MultipartBodyBuilder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.client.EntityExchangeResult;
import org.springframework.test.web.servlet.client.RestTestClient;

/**
 * Media rules found missing in a security review, each test asserting the secure
 * behaviour.
 *
 * <p>Cast: Anna is the admin and owns most items, Ben is the (non-admin) attacker, Carl is
 * a bystander.
 */
@IntegrationTest
@TestPropertySource(properties = "hiwiski.media-quota-per-member=" + MediaSecurityIT.QUOTA_KB + "KB")
@SuppressWarnings("unchecked")
class MediaSecurityIT {

    /** A small quota, so that two photos pass it. */
    static final int QUOTA_KB = 300;

    @Autowired RestTestClient rest;
    @Autowired DSLContext db;

    private Family.Session anna;
    private Family.Session ben;
    private Family.Session carl;

    @BeforeEach
    void family() {
        anna = Family.setUp(rest);
        ben = invite("Ben", "ben");
        carl = invite("Carl", "carl");
    }

    // ---------------------------------------------------------------------------------
    // WebP without a dimension check
    // ---------------------------------------------------------------------------------

    /** A WebP declaring 16384x16384 pixels is refused like an oversized PNG. */
    @Test
    void webpWithHugeDeclaredDimensionsIsRefused() {
        byte[] bomb = webpDeclaring(16384, 16384);

        var result = upload(ben, "MEMBER", ben.memberId(), null, bomb, "image/webp");

        String served = "";
        if (result.getStatus().is2xxSuccessful()) {
            Object id = result.getResponseBody().get("id");
            byte[] preview = rest.get()
                    .uri("/api/v1/images/" + id + "/preview")
                    .headers(carl.auth())
                    .exchange()
                    .expectStatus()
                    .isOk()
                    .expectBody(byte[].class)
                    .returnResult()
                    .getResponseBody();
            served = "; /preview as another member returns the original bytes unchanged: "
                    + Arrays.equals(preview, bomb) + " (" + preview.length + " bytes)";
        }
        assertThat(result.getStatus().value())
                .as("upload of a %d-byte WebP declaring 16384x16384 -> HTTP %s, body %s%s",
                        bomb.length, result.getStatus(), result.getResponseBody(), served)
                .isEqualTo(400);
        assertThat(result.getResponseBody()).containsEntry("code", "media.too_large");
    }

    /** A WebP of a sane size is stored, and now with its size. */
    @Test
    void webpOfASaneSizeIsStoredWithItsSize() {
        var result = upload(ben, "MEMBER", ben.memberId(), null, webpDeclaring(800, 600), "image/webp");

        assertThat(result.getStatus().value()).isEqualTo(201);
        assertThat(result.getResponseBody()).containsEntry("width", 800).containsEntry("height", 600);
    }

    // ---------------------------------------------------------------------------------
    // Originals keep EXIF, GPS included
    // ---------------------------------------------------------------------------------

    /** The original another member downloads says nothing of where it was taken. */
    @Test
    void theOriginalKeepsNoGpsPosition() throws IOException {
        byte[] photo = jpegWithLocation(120, 80);
        assertThat(new String(photo, StandardCharsets.ISO_8859_1)).contains(LOCATION);

        var result = upload(ben, "MEMBER", ben.memberId(), null, photo, "image/jpeg");
        assertThat(result.getStatus().value()).isEqualTo(201);
        byte[] original = rest.get()
                .uri("/api/v1/images/" + result.getResponseBody().get("id"))
                .headers(carl.auth())
                .exchange()
                .expectStatus()
                .isOk()
                .expectBody(byte[].class)
                .returnResult()
                .getResponseBody();

        assertThat(new String(original, StandardCharsets.ISO_8859_1))
                .as("the original as served to another member")
                .doesNotContain(LOCATION)
                .doesNotContain("Exif\0\0MM");
        var image = ImageIO.read(new ByteArrayInputStream(original));
        assertThat(image.getWidth()).isEqualTo(120);
        assertThat(result.getResponseBody()).containsEntry("byteSize", original.length);
    }

    // ---------------------------------------------------------------------------------
    // No storage quota
    // ---------------------------------------------------------------------------------

    /** A member's uploads stop at the quota; another member's still go. */
    @Test
    void uploadsStopAtTheMembersQuota() throws IOException {
        byte[] first = noise(260, 260, 1);
        byte[] second = noise(260, 260, 2);
        assertThat(first.length).as("setup: a photo of more than half the quota").isGreaterThan(QUOTA_KB * 1024 / 2);

        assertThat(upload(ben, "MEMBER", ben.memberId(), null, first, "image/png").getStatus().value())
                .isEqualTo(201);
        var refused = upload(ben, "MEMBER", ben.memberId(), null, second, "image/png");

        assertThat(refused.getStatus().value()).isEqualTo(413);
        assertThat(refused.getResponseBody()).containsEntry("code", "media.quota_exceeded");
        assertThat(upload(carl, "MEMBER", carl.memberId(), null, second, "image/png").getStatus().value())
                .isEqualTo(201);
    }

    /** A PNG of random pixels -- it does not compress. */
    private static byte[] noise(int width, int height, long seed) throws IOException {
        var random = new java.util.Random(seed);
        var image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                image.setRGB(x, y, random.nextInt());
            }
        }
        var out = new ByteArrayOutputStream();
        ImageIO.write(image, "png", out);
        return out.toByteArray();
    }

    // ---------------------------------------------------------------------------------
    // Media id squatting
    // ---------------------------------------------------------------------------------

    /**
     * Ben reads the id of Anna's not-yet-uploaded photo in her page's text and
     * tries to take it first for a page of his own. He cannot; Anna's upload arrives.
     */
    @Test
    void aReaderCannotTakeTheIdOfAnImageNamedInAPageHeCannotChange() throws IOException {
        UUID photo = UUID.randomUUID();
        UUID annasPage = UUID.randomUUID();
        var annas = new SyncClient(rest, anna);
        assertThat(annas.push(SyncClient.mutation("WIKI_PAGE", annasPage, null, Map.of(
                                "title", "Holidays", "kind", "PAGE", "content", "![](hiwiski-image:" + photo + ")")))
                        .getFirst()
                        .get("status"))
                .isEqualTo("applied");
        share(annasPage, ben, "READ");
        UUID bensPage = UUID.randomUUID();
        new SyncClient(rest, ben).push(SyncClient.mutation(
                "WIKI_PAGE", bensPage, null, Map.of(
                        "title", "Decoy", "kind", "PAGE", "content", "![](hiwiski-image:" + photo + ")")));

        var squat = upload(ben, "WIKI_PAGE", bensPage, photo, noise(20, 20, 3), "image/png");
        var own = upload(anna, "WIKI_PAGE", annasPage, photo, noise(20, 20, 4), "image/png");

        assertThat(squat.getStatus().value()).as("Ben's upload under the id in Anna's page").isEqualTo(409);
        assertThat(squat.getResponseBody()).containsEntry("code", "media.id_taken");
        assertThat(own.getStatus().value()).as("Anna's own upload, after Ben's attempt").isEqualTo(201);
        rest.get().uri("/api/v1/images/" + photo).headers(ben.auth()).exchange().expectStatus().isOk();
    }

    /** Nobody takes the id of someone else's picture. */
    @Test
    void nobodyTakesTheIdOfAnotherMembersPicture() throws IOException {
        var picture = upload(carl, "MEMBER", carl.memberId(), null, noise(20, 20, 5), "image/png");
        UUID id = UUID.fromString((String) picture.getResponseBody().get("id"));
        rest.patch()
                .uri("/api/v1/members/" + carl.memberId())
                .headers(carl.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("avatarImageId", id))
                .exchange()
                .expectStatus()
                .isOk();
        // The row is gone (as after a restore that lost it); the profile still names it.
        db.deleteFrom(de.danielkononov.hiwiski.db.generated.Tables.MEDIA)
                .where(de.danielkononov.hiwiski.db.generated.Tables.MEDIA.ID.eq(id))
                .execute();

        assertThat(upload(ben, "MEMBER", ben.memberId(), id, noise(20, 20, 6), "image/png").getStatus().value())
                .isEqualTo(409);
        assertThat(upload(carl, "MEMBER", carl.memberId(), id, noise(20, 20, 7), "image/png").getStatus().value())
                .isEqualTo(201);
    }

    private void share(UUID page, Family.Session with, String level) {
        rest.put()
                .uri("/api/v1/items/WIKI_PAGE/" + page + "/shares")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("shares", List.of(Map.of(
                        "subjectType", "MEMBER", "subjectId", with.memberId().toString(), "level", level))))
                .exchange()
                .expectStatus()
                .isOk();
    }

    // ---------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------

    private EntityExchangeResult<Map> upload(
            Family.Session who, String ownerType, UUID ownerItemId, UUID id, byte[] bytes, String contentType) {
        var body = new MultipartBodyBuilder();
        body.part("ownerType", ownerType);
        body.part("ownerItemId", ownerItemId.toString());
        if (id != null) {
            body.part("id", id.toString());
        }
        body.part("file", new ByteArrayResource(bytes) {
                    @Override
                    public String getFilename() {
                        return "image";
                    }
                })
                .contentType(MediaType.parseMediaType(contentType));
        return rest.post()
                .uri("/api/v1/images")
                .headers(who.auth())
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(body.build())
                .exchange()
                .returnResult(Map.class);
    }

    private static final String LOCATION = "GPSLatitude 52.5200 N, GPSLongitude 13.4050 E";

    /** A JPEG with an EXIF and an XMP block that both hold a position. */
    private static byte[] jpegWithLocation(int width, int height) throws IOException {
        var plain = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "jpg", plain);
        byte[] jpeg = plain.toByteArray();
        var out = new ByteArrayOutputStream();
        out.write(jpeg, 0, 2);
        out.writeBytes(segment(0xe1, "Exif\0\0MM\0*\0\0\0\b\0\0\0\0\0\0" + LOCATION));
        out.writeBytes(segment(0xe1, "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>" + LOCATION + "</x:xmpmeta>"));
        out.write(jpeg, 2, jpeg.length - 2);
        return out.toByteArray();
    }

    private static byte[] segment(int marker, String body) {
        byte[] bytes = body.getBytes(StandardCharsets.ISO_8859_1);
        var out = new ByteArrayOutputStream();
        out.write(0xff);
        out.write(marker);
        out.write((bytes.length + 2) >> 8);
        out.write((bytes.length + 2) & 0xff);
        out.writeBytes(bytes);
        return out.toByteArray();
    }

    /** RIFF/WEBP with a VP8X chunk whose canvas is {@code width} x {@code height}. */
    private static byte[] webpDeclaring(int width, int height) {
        var out = new ByteArrayOutputStream();
        byte[] vp8x = new byte[10];
        // flags (1) + reserved (3) stay zero; then canvas width-1 and height-1, 24 bit LE.
        vp8x[4] = (byte) ((width - 1) & 0xff);
        vp8x[5] = (byte) (((width - 1) >> 8) & 0xff);
        vp8x[6] = (byte) (((width - 1) >> 16) & 0xff);
        vp8x[7] = (byte) ((height - 1) & 0xff);
        vp8x[8] = (byte) (((height - 1) >> 8) & 0xff);
        vp8x[9] = (byte) (((height - 1) >> 16) & 0xff);
        int riffSize = 4 + 8 + vp8x.length;
        out.writeBytes("RIFF".getBytes());
        out.writeBytes(le32(riffSize));
        out.writeBytes("WEBP".getBytes());
        out.writeBytes("VP8X".getBytes());
        out.writeBytes(le32(vp8x.length));
        out.writeBytes(vp8x);
        return out.toByteArray();
    }

    private static byte[] le32(int value) {
        return new byte[] {(byte) value, (byte) (value >> 8), (byte) (value >> 16), (byte) (value >> 24)};
    }

    private Family.Session invite(String displayName, String username) {
        var invitation = rest.post()
                .uri("/api/v1/invitations")
                .headers(anna.auth())
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of("validity", "HOURS_24", "groupIds", List.of()))
                .exchange()
                .expectStatus()
                .isCreated()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody();
        return Family.toSession(rest.post()
                .uri("/api/v1/invitations/" + invitation.get("code") + "/redeem")
                .contentType(MediaType.APPLICATION_JSON)
                .body(Map.of(
                        "displayName", displayName,
                        "username", username,
                        "password", "bens-langes-passwort",
                        "device", Map.of("deviceName", displayName + "s Tablet", "platform", "ANDROID")))
                .exchange()
                .expectStatus()
                .is2xxSuccessful()
                .expectBody(Map.class)
                .returnResult()
                .getResponseBody());
    }
}
