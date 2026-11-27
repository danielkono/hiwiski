package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.MEDIA;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;

import de.danielkononov.hiwiski.platform.KeyedEntityType;
import de.danielkononov.hiwiski.sync.Archive;
import de.danielkononov.hiwiski.sync.SyncField;
import de.danielkononov.hiwiski.sync.SyncProperty;
import de.danielkononov.hiwiski.sync.SyncType;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.JSONB;
import org.jooq.Table;
import org.jooq.TableField;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * What {@code wiki} registers with sync.
 *
 * <p>One bean for every kind: {@code PAGE}, {@code RECIPE} and whatever comes are
 * <strong>one table and one entity type</strong>. A recipe is a page with additional
 * fields, not a type of its own — otherwise the tree would need two queries, moving two
 * paths and sharing two inheritance rules. Those fields are properties
 * the kinds declare ([WikiKind]).
 */
@Configuration
class WikiSyncTypes {

    static final String PAGE_TYPE = "WIKI_PAGE";

    /** A page moved under itself or one of its subpages. */
    static final String MOVE_CYCLE = "wiki.move_cycle";

    /** An image uploaded for another page or member. */
    static final String IMAGE_FOREIGN = "wiki.image_foreign";

    private final DSLContext db;

    /** The kinds of page and their fields. */
    private final List<WikiKind> kinds;

    /** A mind map's elements and connections, which go and come back with their page. */
    private final MindmapSyncTypes mindmaps;

    WikiSyncTypes(DSLContext db, List<WikiKind> kinds, MindmapSyncTypes mindmaps) {
        this.db = db;
        this.kinds = List.copyOf(kinds);
        this.mindmaps = mindmaps;
        var names = new java.util.HashSet<String>();
        for (var kind : this.kinds) {
            for (var property : kind.properties()) {
                if (!names.add(property.name())) {
                    throw new IllegalStateException("wiki: property " + property.name() + " is declared twice");
                }
            }
        }
    }

    private Optional<WikiKind> kind(Object code) {
        return kinds.stream().filter(kind -> kind.code().equals(code)).findFirst();
    }

    /** Every property that holds an image, of any kind. */
    private java.util.Set<String> imageProperties() {
        return kinds.stream()
                .flatMap(kind -> kind.imageProperties().stream())
                .collect(java.util.stream.Collectors.toSet());
    }

    @Bean
    SyncType wikiPageSyncType() {
        return new SyncType() {
            @Override
            public String entityType() {
                return PAGE_TYPE;
            }

            @Override
            public Table<?> table() {
                return WIKI_PAGE;
            }

            @Override
            public List<SyncField<?>> fields() {
                return List.of(
                        SyncField.uuid("parentId", WIKI_PAGE.PARENT_ID),
                        SyncField.integer("position", WIKI_PAGE.POSITION),
                        SyncField.text("kind", WIKI_PAGE.KIND),
                        SyncField.text("title", WIKI_PAGE.TITLE),
                        SyncField.uuidArray("tags", WIKI_PAGE.TAGS),
                        SyncField.text("content", WIKI_PAGE.CONTENT),
                        // Per page, not inherited: "only this page" has to be
                        // expressible.
                        SyncField.timestamp(Archive.ARCHIVED_AT, WIKI_PAGE.ARCHIVED_AT),
                        SyncField.uuid(Archive.ARCHIVED_BY, WIKI_PAGE.ARCHIVED_BY));
            }

            /** What the kinds add: a recipe's servings, ingredients …. */
            @Override
            public List<SyncProperty> properties() {
                return kinds.stream().flatMap(kind -> kind.properties().stream()).toList();
            }

            @Override
            public Optional<Field<JSONB>> propertiesColumn() {
                return Optional.of(WIKI_PAGE.PROPERTIES);
            }

            /**
             * An archived page is read-only, and nothing new goes under it
             * (archive).
             *
             * <p>The target parent is only checked when the page is created or moved: a
             * subpage left active under an archived parent stays editable — that is what
             * "only this page" means.
             */
            @Override
            public Optional<String> refusal(
                    UUID entityId, boolean exists, UUID containerId, java.util.Map<String, Object> fields) {
                if (exists && archived(entityId) && !Archive.onlyArchiveFields(fields)) {
                    return Optional.of(Archive.READ_ONLY);
                }
                boolean placed = !exists || (fields != null && fields.containsKey("parentId"));
                if (placed) {
                    UUID parent = fields != null && fields.containsKey("parentId")
                            ? (fields.get("parentId") == null ? null : UUID.fromString(fields.get("parentId").toString()))
                            : containerId;
                    if (parent != null && archived(parent)) {
                        return Optional.of(Archive.READ_ONLY);
                    }
                    if (parent != null && exists && below(parent, entityId)) {
                        return Optional.of(MOVE_CYCLE);
                    }
                }
                if (fields != null) {
                    for (String name : imageProperties()) {
                        if (fields.get(name) != null && !imageOf(entityId, fields.get(name))) {
                            return Optional.of(IMAGE_FOREIGN);
                        }
                    }
                }
                return Optional.empty();
            }

            @Override
            public java.util.Map<String, Object> stamped(
                    UUID actor, java.time.OffsetDateTime now, java.util.Map<String, Object> fields) {
                return Archive.stamped(fields, actor, now);
            }

            /**
             * A page's container is its parent page — and the root has none.
             *
             * <p>That way a subpage inherits the share of its branch, and a moved branch
             * inherits that of its new place.
             */
            @Override
            public Optional<Container> container() {
                return Optional.of(new Container(PAGE_TYPE, WIKI_PAGE.PARENT_ID));
            }

            /**
             * The number depends on the kind: {@code WIKI-3} for a page, {@code REC-12}
             * for a recipe — a kind's own range where it has one ([WikiKind.keyType]).
             */
            @Override
            public Optional<KeyedEntityType> keyType() {
                return Optional.of(KeyedEntityType.WIKI_PAGE);
            }

            @Override
            public Optional<KeyedEntityType> keyType(java.util.Map<String, Object> fields) {
                return Optional.of(kind(fields.get("kind"))
                        .flatMap(WikiKind::keyType)
                        .orElse(KeyedEntityType.WIKI_PAGE));
            }

            @Override
            public Optional<TableField<?, String>> keyColumn() {
                return Optional.of(WIKI_PAGE.ENTITY_KEY);
            }

            /**
             * Whether the image was uploaded for this page (no reuse).
             *
             * <p>An image lives as long as its carrier, and who may see it follows the
             * carrier. Set on another page, the weekly cleanup took it away after a day
             * -- clearing that page's image too -- and readers of the other page who could
             * not see the carrier got a 404.
             */
            private boolean imageOf(UUID pageId, Object imageId) {
                UUID image;
                try {
                    image = UUID.fromString(imageId.toString());
                } catch (IllegalArgumentException notAnId) {
                    return false;
                }
                return db.fetchExists(db.selectOne()
                        .from(MEDIA)
                        .where(MEDIA.ID.eq(image))
                        .and(MEDIA.ITEM_TYPE.eq(PAGE_TYPE))
                        .and(MEDIA.ITEM_ID.eq(pageId)));
            }

            /**
             * Whether {@code page} is {@code ancestor} itself or lies below it.
             *
             * <p>A page moved under itself or one of its subpages forms a cycle without a
             * root: the branch vanishes from the tree, share inheritance runs into its
             * depth limit, and breadcrumbs repeat titles. Two crossing moves cannot both
             * pass: pushes are applied one after the other, under the change sequence's
             * lock.
             */
            private boolean below(UUID page, UUID ancestor) {
                UUID current = page;
                for (int depth = 0; current != null && depth < 256; depth++) {
                    if (current.equals(ancestor)) {
                        return true;
                    }
                    current = db.select(WIKI_PAGE.PARENT_ID)
                            .from(WIKI_PAGE)
                            .where(WIKI_PAGE.ID.eq(current))
                            .fetchOne(WIKI_PAGE.PARENT_ID);
                }
                return current != null;
            }

            private boolean archived(UUID pageId) {
                return db.fetchExists(db.selectOne()
                        .from(WIKI_PAGE)
                        .where(WIKI_PAGE.ID.eq(pageId))
                        .and(WIKI_PAGE.ARCHIVED_AT.isNotNull()));
            }

            /**
             * <strong>What goes along with a delete has to be enumerated</strong>.
             *
             * <p>A deleted branch takes everything below it along — recursively, since a
             * page can be nested to any depth. {@code on delete cascade} only applies to
             * a hard delete, and here the delete is soft.
             */
            @Override
            public List<Ref> alsoDeleted(UUID entityId) {
                var subpages = db.select(WIKI_PAGE.ID)
                        .from(WIKI_PAGE)
                        .where(WIKI_PAGE.PARENT_ID.eq(entityId))
                        .and(WIKI_PAGE.DELETED_AT.isNull())
                        .fetch(WIKI_PAGE.ID)
                        .stream()
                        .map(id -> new Ref(PAGE_TYPE, id));
                // A mind map's elements and connections: left alive, they stayed on the
                // devices and in the page's references after the page had gone.
                return java.util.stream.Stream.concat(subpages, mindmaps.livingOn(entityId).stream())
                        .toList();
            }

            /**
             * A mind map's elements and connections come back with their page. They have
             * no entry of their own in the trash, and the page came back empty without
             * them. Subpages do have one each and are restored on their own.
             */
            @Override
            public List<Ref> alsoRestored(UUID entityId, java.time.OffsetDateTime deletedAt) {
                return mindmaps.deletedWith(entityId, deletedAt);
            }
        };
    }
}
