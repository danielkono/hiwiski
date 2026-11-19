package de.danielkononov.hiwiski.admin.internal;

import de.danielkononov.hiwiski.api.TrashApi;
import de.danielkononov.hiwiski.api.model.RestoreRequest;
import de.danielkononov.hiwiski.api.model.TrashEntry;
import de.danielkononov.hiwiski.api.model.TrashList;
import de.danielkononov.hiwiski.identity.CurrentUser;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class TrashController implements TrashApi {

    private final TrashService trash;

    TrashController(TrashService trash) {
        this.trash = trash;
    }

    @Override
    public ResponseEntity<TrashList> listTrash(String itemType) {
        var principal = CurrentUser.require();
        var entries = trash.forMember(principal.memberId(), itemType).stream()
                .map(entry -> {
                    TrashEntry api = new TrashEntry(
                            entry.itemType(),
                            entry.itemId(),
                            entry.title(),
                            OffsetDateTime.ofInstant(entry.deletedAt(), ZoneOffset.UTC),
                            entry.remainingDays(),
                            entry.restorable());
                    api.setEntityKey(entry.entityKey());
                    api.setDeletedBy(entry.deletedBy());
                    return api;
                })
                .toList();
        return ResponseEntity.ok(new TrashList(entries, trash.retentionDays()));
    }

    @Override
    public ResponseEntity<Void> restoreFromTrash(String itemType, UUID itemId, RestoreRequest request) {
        trash.restore(
                CurrentUser.requireMemberId(),
                itemType,
                itemId,
                request == null ? null : request.getTargetContainerId());
        return ResponseEntity.noContent().build();
    }
}
