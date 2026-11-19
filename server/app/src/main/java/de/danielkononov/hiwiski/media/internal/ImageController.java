package de.danielkononov.hiwiski.media.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;
import static de.danielkononov.hiwiski.db.generated.Tables.MEMBER;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.api.ImagesApi;
import de.danielkononov.hiwiski.api.model.ImageInfo;
import de.danielkononov.hiwiski.db.generated.tables.records.MediaRecord;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.io.IOException;
import java.time.Duration;
import java.util.Set;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * The media store: upload, serve, keep in two sizes.
 *
 * <p><strong>Not a file module.</strong> Every image names its carrier on upload, and
 * whoever uploads must be allowed to edit the carrier. There is no share of its own: an
 * image is visible if its carrier is visible — and the same {@code 404} for "does not
 * exist" and "you cannot see it".
 */
@RestController
class ImageController implements ImagesApi {

    /**
     * Pages and recipes — both are {@code WIKI_PAGE} —, a list's and a task's
     * description, an event's note, and a member's own picture.
     */
    private static final Set<String> OWNER_TYPES =
            Set.of("WIKI_PAGE", "TODO_LIST", "TODO", "EVENT", MediaCarriers.MEMBER);

    /**
     * An image never changes: a new version is a new image with a new ID. The client may
     * therefore keep it as long as it likes.
     */
    private static final CacheControl IMMUTABLE =
            CacheControl.maxAge(Duration.ofDays(365)).cachePrivate().immutable();

    private final DSLContext db;
    private final Access access;
    private final MediaStore store;
    private final UploadLimits limits;
    private final MediaReferences references;

    ImageController(
            DSLContext db, Access access, MediaStore store, UploadLimits limits, MediaReferences references) {
        this.db = db;
        this.access = access;
        this.store = store;
        this.limits = limits;
        this.references = references;
    }

    /**
     * Not one transaction: reading up to 25 MB, hashing, decoding and writing files held
     * a pooled connection all along for a single insert, and a few large photos at once
     * left sync waiting for one. The insert commits on its own; until it does, the file
     * is protected from the cleanup by its age.
     */
    @Override
    public ResponseEntity<ImageInfo> uploadImage(
            String ownerType, UUID ownerItemId, MultipartFile file, UUID requestedId) throws IOException {
        var memberId = CurrentUser.requireMemberId();
        if (!OWNER_TYPES.contains(ownerType)) {
            throw HiwiskiException.invalid("media.owner_type_invalid", "ownerType", ownerType);
        }
        if (MediaCarriers.MEMBER.equals(ownerType)) {
            // One's own picture only: a profile is not shared, it is one's own.
            if (!memberId.equals(ownerItemId)) {
                throw HiwiskiException.forbidden("media.owner_read_only");
            }
        } else {
            var level = access.levelOf(memberId, ownerType, ownerItemId);
            if (level.isEmpty()) {
                throw HiwiskiException.notFound("media.owner_not_found", "ownerItemId", ownerItemId);
            }
            if (!level.get().atLeast(AccessLevel.WRITE)) {
                throw HiwiskiException.forbidden("media.owner_read_only");
            }
        }

        // A few at a time: each one is read onto the heap whole, and decoded. Everything
        // after the access check happens in the turn -- the reference scan over every
        // page and revision, the quota and the row that counts towards it -- so a burst
        // of uploads neither loads the database without bound nor passes the quota all
        // at once: the overshoot is at most one upload per other turn.
        return limits.inTurn(() -> upload(memberId, ownerType, ownerItemId, file, requestedId));
    }

    private ResponseEntity<ImageInfo> upload(
            UUID memberId, String ownerType, UUID ownerItemId, MultipartFile file, UUID requestedId) {
        // An id the app brings: the carrier points to it already. Sent twice
        // -- the answer lost on the way -- it is the same upload; under anyone else's
        // image or another carrier it is refused, never overwritten.
        if (requestedId != null) {
            var existing = db.selectFrom(MEDIA).where(MEDIA.ID.eq(requestedId)).fetchOne();
            if (existing != null) {
                return sameUpload(existing, memberId, ownerType, ownerItemId);
            }
            // A new id that an item the uploader sees but may not change already
            // names: they learned it there, and may not decide what that item shows. A
            // member with only READ on a page saw the id in its text before the
            // author's device uploaded the photo, took it first for a page of their
            // own, and the author's app threw its only copy away on the 409. An item the uploader cannot see does not count:
            // the squatter's own copy of the reference must not lock the author out.
            for (var carrier : references.carriersNaming(requestedId)) {
                boolean stated = carrier.type().equals(ownerType) && carrier.id().equals(ownerItemId);
                if (!stated && carrierVisible(memberId, carrier.type(), carrier.id()) && !canChange(memberId, carrier)) {
                    throw HiwiskiException.conflict("media.id_taken", "id", requestedId);
                }
            }
        }

        limits.checkQuota(memberId, file.getSize());
        MediaStore.Stored stored;
        try {
            stored = store.put(file.getBytes());
        } catch (IOException e) {
            throw new java.io.UncheckedIOException(e);
        }
        var id = requestedId == null ? UUID.randomUUID() : requestedId;
        try {
            db.insertInto(MEDIA)
                    .set(MEDIA.ID, id)
                    .set(MEDIA.OWNER_ID, memberId)
                    .set(MEDIA.CONTENT_TYPE, stored.contentType())
                    .set(MEDIA.BYTE_SIZE, stored.byteSize())
                    .set(MEDIA.WIDTH, stored.width())
                    .set(MEDIA.HEIGHT, stored.height())
                    .set(MEDIA.SHA256, stored.sha256())
                    .set(MEDIA.ITEM_TYPE, ownerType)
                    .set(MEDIA.ITEM_ID, ownerItemId)
                    .execute();
        } catch (org.springframework.dao.DuplicateKeyException
                | org.jooq.exception.IntegrityConstraintViolationException taken) {
            // The same new id from two uploads at once -- a retry while the first still
            // ran, or someone racing the author: whichever row committed first decides,
            // as if this one had come second. It used to be a 500.
            var existing = requestedId == null
                    ? null
                    : db.selectFrom(MEDIA).where(MEDIA.ID.eq(requestedId)).fetchOne();
            if (existing == null) {
                throw taken;
            }
            return sameUpload(existing, memberId, ownerType, ownerItemId);
        }

        var info = new ImageInfo(id, stored.contentType(), stored.byteSize());
        info.setWidth(stored.width());
        info.setHeight(stored.height());
        return ResponseEntity.status(HttpStatus.CREATED).body(info);
    }

    /**
     * The answer for an id that has a row: the same upload again, or {@code 409}.
     *
     * <p>The same {@code 409} whether or not the uploader can see the image that has
     * the id: whose it is and where it hangs are not looked at beyond "not this
     * upload's". The answer says only that the id is taken -- an id the uploader already
     * knows, since a random UUID is not guessed.
     */
    private static ResponseEntity<ImageInfo> sameUpload(
            MediaRecord existing, UUID memberId, String ownerType, UUID ownerItemId) {
        if (!memberId.equals(existing.getOwnerId())
                || !ownerType.equals(existing.getItemType())
                || !ownerItemId.equals(existing.getItemId())) {
            throw HiwiskiException.conflict("media.id_taken", "id", existing.getId());
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(info(existing));
    }

    private boolean canChange(UUID memberId, MediaReferences.Carrier carrier) {
        if (MediaCarriers.MEMBER.equals(carrier.type())) {
            return memberId.equals(carrier.id());
        }
        return access.levelOf(memberId, carrier.type(), carrier.id())
                .map(level -> level.atLeast(AccessLevel.WRITE))
                .orElse(false);
    }

    private static ImageInfo info(MediaRecord row) {
        var info = new ImageInfo(row.getId(), row.getContentType(), row.getByteSize());
        info.setWidth(row.getWidth());
        info.setHeight(row.getHeight());
        return info;
    }

    @Override
    public ResponseEntity<Resource> getImage(UUID id) {
        var row = visible(id);
        return serve(store.original(row.getSha256()), row.getContentType());
    }

    @Override
    public ResponseEntity<Resource> getImagePreview(UUID id) {
        var row = visible(id);
        var preview = store.preview(row.getSha256());
        // Where no preview could be made (a format Java cannot read), the original is
        // the preview — a missing image would be worse than a large one.
        return preview == null
                ? serve(store.original(row.getSha256()), row.getContentType())
                : serve(preview, MediaStore.PREVIEW_TYPE);
    }

    private MediaRecord visible(UUID id) {
        var memberId = CurrentUser.requireMemberId();
        var row = db.selectFrom(MEDIA).where(MEDIA.ID.eq(id)).fetchOne();
        if (row == null
                || row.getSha256() == null
                || row.getItemId() == null
                || !carrierVisible(memberId, row.getItemType(), row.getItemId())) {
            throw HiwiskiException.notFound("media.image_not_found", "id", id);
        }
        return row;
    }

    /** A member's picture is seen by the whole family, like the member list; the rest by access. */
    private boolean carrierVisible(UUID memberId, String itemType, UUID itemId) {
        if (MediaCarriers.MEMBER.equals(itemType)) {
            return db.fetchExists(MEMBER, MEMBER.ID.eq(itemId));
        }
        return access.levelOf(memberId, itemType, itemId).isPresent();
    }

    private static ResponseEntity<Resource> serve(java.nio.file.Path path, String contentType) {
        if (!java.nio.file.Files.isRegularFile(path)) {
            // A row whose file is gone: not found, not a server error on every load.
            throw HiwiskiException.notFound("media.image_not_found", "file", path.getFileName().toString());
        }
        return ResponseEntity.ok()
                .cacheControl(IMMUTABLE)
                .contentType(MediaType.parseMediaType(contentType))
                .body(new FileSystemResource(path));
    }
}
