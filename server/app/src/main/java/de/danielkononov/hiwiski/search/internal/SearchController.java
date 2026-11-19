package de.danielkononov.hiwiski.search.internal;

import static de.danielkononov.hiwiski.db.generated.Tables.CHANGE_LOG;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO;
import static de.danielkononov.hiwiski.db.generated.Tables.TODO_LIST;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.api.SearchApi;
import de.danielkononov.hiwiski.api.model.History;
import de.danielkononov.hiwiski.api.model.HistoryEntry;
import de.danielkononov.hiwiski.api.model.SearchHit;
import de.danielkononov.hiwiski.api.model.SearchResult;
import de.danielkononov.hiwiski.api.model.TodoStatus;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.sync.Archive;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;
import org.jooq.Condition;
import org.jooq.DSLContext;
import org.jooq.Field;
import org.jooq.impl.DSL;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/** Search and history. */
@RestController
class SearchController implements SearchApi {

    /** {@code TD-14}, {@code WIKI-3} — prefix and number, the way the key is built. */
    private static final Pattern KEY = Pattern.compile("^#?([A-Za-z][A-Za-z0-9]{0,7})-(\\d+)$");

    private static final String LIST_TYPE = "TODO_LIST";
    private static final String TODO_TYPE = "TODO";

    private static final List<String> HISTORY_OPS = java.util.Arrays.stream(HistoryEntry.OpEnum.values())
            .map(HistoryEntry.OpEnum::getValue)
            .toList();

    /**
     * The status the change wrote. The field name alone says "Done" both for checking off
     * and for opening again; the reader needs the direction.
     */
    private static final Field<String> STATUS_WRITTEN =
            DSL.field("{0} ->> 'status'", String.class, CHANGE_LOG.FIELDS);

    /** Likewise for the archive: archiving and restoring both touch {@code archivedAt}. */
    private static final Field<String> ARCHIVED_AT_WRITTEN =
            DSL.field("{0} ->> 'archivedAt'", String.class, CHANGE_LOG.FIELDS);

    /** And for a card: "changed: Column" did not say where it went. */
    private static final Field<String> COLUMN_WRITTEN =
            DSL.field("{0} ->> 'columnId'", String.class, CHANGE_LOG.FIELDS);

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final DSLContext db;
    private final SearchService search;
    private final Access access;
    private final InstanceSettings settings;

    SearchController(DSLContext db, SearchService search, Access access, InstanceSettings settings) {
        this.db = db;
        this.search = search;
        this.access = access;
        this.settings = settings;
    }

    @Override
    public ResponseEntity<SearchResult> search(String q, List<String> types, Boolean includeArchived) {
        var principal = CurrentUser.require();
        var result = new SearchResult(List.of());

        // **An entered number jumps straight to the item** instead of running a
        // full-text search.
        if (q != null && KEY.matcher(q.trim()).matches()) {
            search.byEntityKey(q.trim().replaceFirst("^#", ""), principal.memberId())
                    .ifPresent(hit -> result.setJumpTo(toApi(hit)));
        }

        result.setHits(search.search(q, principal.memberId(), types, Boolean.TRUE.equals(includeArchived)).stream()
                .map(SearchController::toApi)
                .toList());
        return ResponseEntity.ok(result);
    }

    @Override
    public ResponseEntity<History> getHistory(String itemType, UUID itemId) {
        var principal = CurrentUser.require();
        // 404 and not 403: whoever may not see the item should not be able to tell from
        // the response that it exists.
        if (!access.may(principal.memberId(), itemType, itemId, AccessLevel.READ)) {
            throw HiwiskiException.notFound("history.item_not_found", "itemId", itemId);
        }

        // A list's history also holds its tasks': ticked off or deleted, a task left the
        // list without a trace on it, and one had to open every task to find out. Whoever
        // reads the list reads its tasks (the share cascades). The tasks
        // in it now, deleted ones too -- a task moved away takes its changes along.
        Condition item = CHANGE_LOG.ENTITY_TYPE.eq(itemType).and(CHANGE_LOG.ENTITY_ID.eq(itemId));
        Condition scope = LIST_TYPE.equals(itemType)
                ? item.or(CHANGE_LOG.ENTITY_TYPE
                        .eq(TODO_TYPE)
                        .and(CHANGE_LOG.ENTITY_ID.in(
                                DSL.select(TODO.ID).from(TODO).where(TODO.LIST_ID.eq(itemId)))))
                : item;

        // `changed_fields` instead of picking `fields` apart afterwards: the column
        // carries exactly this information, and for an upsert with only changed fields
        // it could not be reconstructed reliably.
        var entries = db.select(
                        CHANGE_LOG.SEQ,
                        CHANGE_LOG.RECORDED_AT,
                        CHANGE_LOG.ACTOR_MEMBER_ID,
                        CHANGE_LOG.OP,
                        CHANGE_LOG.CHANGED_FIELDS,
                        STATUS_WRITTEN,
                        ARCHIVED_AT_WRITTEN,
                        CHANGE_LOG.ENTITY_TYPE,
                        CHANGE_LOG.ENTITY_ID,
                        TODO.TITLE,
                        COLUMN_WRITTEN,
                        TODO_LIST.COLUMNS)
                .from(CHANGE_LOG)
                .leftJoin(TODO)
                .on(CHANGE_LOG.ENTITY_TYPE.eq(TODO_TYPE).and(TODO.ID.eq(CHANGE_LOG.ENTITY_ID)))
                .leftJoin(TODO_LIST)
                .on(TODO_LIST.ID.eq(TODO.LIST_ID))
                .where(scope)
                // Only changes to the items themselves. The synthetic entries
                // `access_granted`/`access_revoked` go to individual recipients and are
                // not history -- and their `op` is not in the contract: `fromValue` threw,
                // and every assigned item got a 400 instead of a history.
                .and(CHANGE_LOG.OP.in(HISTORY_OPS))
                .orderBy(CHANGE_LOG.SEQ.desc())
                .fetch()
                .map(row -> {
                    var entry = new HistoryEntry(
                            row.value1(),
                            row.value2(),
                            HistoryEntry.OpEnum.fromValue(row.value4()));
                    entry.setActorId(row.value3());
                    entry.setFields(row.value5() == null
                            ? List.of()
                            : java.util.Arrays.stream(row.value5()).sorted().toList());
                    // Only where the change touched the status: `fields` may also carry
                    // values that were sent along unchanged.
                    if (entry.getFields().contains("status")) {
                        entry.setStatus(toStatus(row.value6()));
                    }
                    if (entry.getFields().contains(Archive.ARCHIVED_AT)) {
                        entry.setArchived(row.value7() != null);
                    }
                    if (entry.getFields().contains("columnId")) {
                        entry.setColumn(columnName(row.value12(), row.value11()));
                    }
                    if (!row.value8().equals(itemType)) {
                        entry.setEntryId(row.value9());
                        entry.setEntryTitle(row.value10());
                    }
                    return entry;
                });

        // **The log retention period also limits how far back the history reaches — and
        // the UI says so**. Without this value a truncated history looks
        // like a complete one.
        int days = settings.getInt(SettingKey.RETENTION_LOG_DAYS, 90);
        var reachesBack = OffsetDateTime.now().minusDays(days);

        return ResponseEntity.ok(new History(entries, reachesBack));
    }

    /**
     * The name the board gives the column [columnId] now -- null once the column is gone,
     * or for a board whose columns cannot be read.
     */
    private static String columnName(org.jooq.JSONB columns, String columnId) {
        if (columns == null || columns.data() == null || columnId == null) {
            return null;
        }
        try {
            for (var column : JSON.readTree(columns.data())) {
                if (columnId.equals(column.path("id").asString(null))) {
                    return column.path("name").asString(null);
                }
            }
        } catch (tools.jackson.core.JacksonException unreadable) {
            return null;
        }
        return null;
    }

    /** Null for a value outside the contract, instead of a 500 for the whole history. */
    private static TodoStatus toStatus(String value) {
        return java.util.Arrays.stream(TodoStatus.values())
                .filter(status -> status.getValue().equals(value))
                .findFirst()
                .orElse(null);
    }

    private static SearchHit toApi(SearchService.Hit hit) {
        var api = new SearchHit(hit.itemType(), hit.itemId(), hit.title());
        api.setEntityKey(hit.entityKey());
        api.setContext(hit.context());
        api.setSnippet(hit.snippet());
        api.setArchived(hit.archived());
        return api;
    }
}
