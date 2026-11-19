package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.sync.SyntheticChanges;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Component
class SyntheticChangeWriter implements SyntheticChanges {

    private final ChangeLogRepository changeLog;

    SyntheticChangeWriter(ChangeLogRepository changeLog) {
        this.changeLog = changeLog;
    }

    /**
     * In the same transaction as the share change.
     *
     * <p>Otherwise a pull could slip in between that already sees the new share but not
     * the order to pull the history — and the history would be missing for good.
     */
    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public void append(long seq, String op, String itemType, UUID itemId, UUID recipient) {
        changeLog.append(
                seq,
                itemType,
                itemId,
                null,
                null,
                op,
                Map.of(),
                List.of(),
                // The recipient is recorded as the actor: the entry goes only to them.
                // Anyone else who saw it would learn who was shared what.
                recipient,
                null,
                seq);
    }
}
