package de.danielkononov.hiwiski.todo.internal;

import de.danielkononov.hiwiski.api.TodoApi;
import de.danielkononov.hiwiski.api.model.ListSummary;
import de.danielkononov.hiwiski.identity.CurrentUser;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * The one read of lists over REST: what a home screen widget shows while the app is
 * closed. Lists and tasks are written exclusively through the sync.
 */
@RestController
class TodoController implements TodoApi {

    private final ListSummaryService summaries;

    TodoController(ListSummaryService summaries) {
        this.summaries = summaries;
    }

    @Override
    public ResponseEntity<ListSummary> getListSummary(UUID listId, UUID columnId, Integer limit) {
        var principal = CurrentUser.require();
        return ResponseEntity.ok(summaries.summary(
                principal.memberId(),
                listId,
                columnId,
                limit == null ? ListSummaryService.DEFAULT_LIMIT : limit));
    }
}
