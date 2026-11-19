package de.danielkononov.hiwiski.access.internal;

import de.danielkononov.hiwiski.access.Access;
import de.danielkononov.hiwiski.access.AccessLevel;
import de.danielkononov.hiwiski.api.AccessApi;
import de.danielkononov.hiwiski.api.model.ShareEntry;
import de.danielkononov.hiwiski.api.model.ShareSheet;
import de.danielkononov.hiwiski.api.model.ShareSubjectType;
import de.danielkononov.hiwiski.api.model.WriteSharesRequest;
import de.danielkononov.hiwiski.identity.CurrentUser;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

/**
 * The share sheet.
 *
 * <p>The same on every item — from the bottom on a phone, as a dialog on desktop, but one
 * component.
 */
@RestController
class ShareController implements AccessApi {

    private final AccessService access;
    private final EffectiveAccessService effective;

    ShareController(AccessService access, EffectiveAccessService effective) {
        this.access = access;
        this.effective = effective;
    }

    @Override
    public ResponseEntity<ShareSheet> getShares(String itemType, UUID itemId) {
        return ResponseEntity.ok(sheet(itemType, itemId, CurrentUser.require()));
    }

    @Override
    public ResponseEntity<ShareSheet> setShares(String itemType, UUID itemId, WriteSharesRequest request) {
        var principal = CurrentUser.require();
        var rows = request.getShares().stream()
                .map(share -> new ShareRepository.ShareRow(
                        Access.SubjectType.valueOf(share.getSubjectType().getValue()),
                        share.getSubjectId(),
                        AccessLevel.parse(share.getLevel().getValue())))
                .toList();
        access.replace(itemType, itemId, rows, principal.memberId());
        return ResponseEntity.ok(sheet(itemType, itemId, principal));
    }

    private ShareSheet sheet(String itemType, UUID itemId, CurrentUser.Principal principal) {
        var ownable = effective.ownable(itemType)
                .orElseThrow(() -> HiwiskiException.invalid("access.unknown_item_type", "itemType", itemType));
        UUID owner = ownable.ownerOf(itemId)
                .orElseThrow(() -> HiwiskiException.notFound("access.item_not_found", "itemId", itemId));

        // 404 and not 403: whoever may not see the item should not be able to tell from
        // the response that it exists.
        AccessLevel myLevel = access.levelOf(principal.memberId(), itemType, itemId)
                .orElseThrow(() -> HiwiskiException.notFound("access.item_not_found", "itemId", itemId));

        var entries = access.grantsOn(itemType, itemId).stream()
                .map(grant -> {
                    ShareEntry entry = new ShareEntry(
                            ShareSubjectType.fromValue(grant.subjectType().name()),
                            grant.subjectId(),
                            de.danielkononov.hiwiski.api.model.AccessLevel.fromValue(grant.level().name()),
                            de.danielkononov.hiwiski.api.model.ShareSource.fromValue(grant.source().name()));
                    return entry;
                })
                .toList();

        // Whoever may not change the share still sees the sheet -- read-only. Knowing who
        // sees something is not a privilege.
        ShareSheet sheet = new ShareSheet(itemType, itemId, owner.equals(principal.memberId()), entries);
        sheet.setOwnerId(owner);
        sheet.setMyLevel(de.danielkononov.hiwiski.api.model.AccessLevel.fromValue(myLevel.name()));
        effective.inheritsFrom(itemType, itemId).ifPresent(container -> {
            sheet.setInheritedFromType(container.itemType());
            sheet.setInheritedFromId(container.itemId());
        });
        return sheet;
    }
}
