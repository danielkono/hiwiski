package de.danielkononov.hiwiski.wiki.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_PAGE;
import static de.danielkononov.hiwiski.db.generated.Tables.WIKI_REVISION;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.api.WikiApi;
import de.danielkononov.hiwiski.api.model.ImportRecipeRequest;
import de.danielkononov.hiwiski.api.model.LinkList;
import de.danielkononov.hiwiski.api.model.LinkRef;
import de.danielkononov.hiwiski.api.model.ParsedIngredient;
import de.danielkononov.hiwiski.api.model.ParsedRecipe;
import de.danielkononov.hiwiski.api.model.Revision;
import de.danielkononov.hiwiski.api.model.RevisionList;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.link.Links;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.List;
import java.util.UUID;
import org.jooq.DSLContext;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/** History, references and recipe import. The pages themselves go through sync. */
@RestController
class WikiController implements WikiApi {

    private final DSLContext db;
    private final Access access;
    private final Links links;
    private final RecipeImporter importer;

    WikiController(DSLContext db, Access access, Links links, RecipeImporter importer) {
        this.db = db;
        this.access = access;
        this.links = links;
        this.importer = importer;
    }

    @Override
    public ResponseEntity<RevisionList> listRevisions(UUID pageId) {
        requireRead(pageId);

        var revisions = db.selectFrom(WIKI_REVISION)
                .where(WIKI_REVISION.PAGE_ID.eq(pageId))
                .orderBy(WIKI_REVISION.SEQ.desc())
                .fetch()
                .map(row -> {
                    // Without text: the history is a list, not a pile of full texts.
                    var revision = new Revision(
                            row.getId(),
                            row.getSeq(),
                            row.getTitle(),
                            row.getCreatedAt(),
                            Revision.KindEnum.fromValue(row.getKind()));
                    revision.setAuthorId(row.getAuthorId());
                    revision.setChangeSeq(row.getChangeSeq());
                    return revision;
                });

        return ResponseEntity.ok(new RevisionList(revisions));
    }

    @Override
    public ResponseEntity<Revision> getRevision(UUID pageId, UUID revisionId) {
        requireRead(pageId);

        var row = db.selectFrom(WIKI_REVISION)
                .where(WIKI_REVISION.ID.eq(revisionId))
                .and(WIKI_REVISION.PAGE_ID.eq(pageId))
                .fetchOne();
        if (row == null) {
            throw HiwiskiException.notFound("wiki.revision_not_found", "revisionId", revisionId);
        }

        var revision = new Revision(
                row.getId(),
                row.getSeq(),
                row.getTitle(),
                row.getCreatedAt(),
                Revision.KindEnum.fromValue(row.getKind()));
        revision.setAuthorId(row.getAuthorId());
        revision.setContent(row.getContent());
        return ResponseEntity.ok(revision);
    }

    @Override
    public ResponseEntity<LinkList> getLinks(String itemType, UUID itemId) {
        var principal = CurrentUser.require();
        // Asking for an item's references also requires being allowed to see it:
        // otherwise a non-empty response would reveal that the item exists. 404 and not
        // 403, as everywhere.
        if (!access.may(principal.memberId(), itemType, itemId, AccessLevel.READ)) {
            throw HiwiskiException.notFound("link.item_not_found", "itemId", itemId);
        }
        var list = new LinkList(
                refs(links.outgoing(itemType, itemId, principal.memberId())),
                refs(links.incoming(itemType, itemId, principal.memberId())));
        return ResponseEntity.ok(list);
    }

    @Override
    public ResponseEntity<ParsedRecipe> importRecipe(ImportRecipeRequest request) {
        CurrentUser.require();

        var recipe = importer.fetch(request.getUrl());
        var parsed = new ParsedRecipe(
                recipe.title() == null ? "" : recipe.title(),
                recipe.ingredients().stream()
                        .map(item -> {
                            var line = new ParsedIngredient(item.label(), item.uncertain());
                            line.setAmount(item.amount());
                            line.setUnit(item.unit());
                            return line;
                        })
                        .toList());
        parsed.setServings(recipe.servings());
        parsed.setDurationMinutes(recipe.durationMinutes());
        parsed.setImageUrl(recipe.imageUrl());
        parsed.setSourceUrl(recipe.sourceUrl());
        parsed.setContent(recipe.content());
        return ResponseEntity.ok(parsed);
    }

    private static List<LinkRef> refs(List<Links.Ref> refs) {
        return refs.stream()
                .map(ref -> {
                    var out = new LinkRef(ref.itemType(), ref.itemId(), ref.title());
                    out.setEntityKey(ref.entityKey());
                    return out;
                })
                .toList();
    }

    /**
     * 404 and not 403: whoever may not see the page should not be able to tell from the
     * response that it exists.
     */
    private void requireRead(UUID pageId) {
        var principal = CurrentUser.require();
        boolean exists = db.fetchExists(db.selectFrom(WIKI_PAGE).where(WIKI_PAGE.ID.eq(pageId)));
        if (!exists
                || !access.may(principal.memberId(), WikiSyncTypes.PAGE_TYPE, pageId, AccessLevel.READ)) {
            throw HiwiskiException.notFound("wiki.page_not_found", "pageId", pageId);
        }
    }
}
