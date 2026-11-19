package de.danielkononov.hiwiski.sync.internal;

import de.danielkononov.hiwiski.api.model.ChangeEnvelope;
import de.danielkononov.hiwiski.platform.HiwiskiException;
import de.danielkononov.hiwiski.sync.SyncRegistry;
import de.danielkononov.hiwiski.sync.VisibleItems;
import java.util.List;
import java.util.UUID;
import org.jooq.Condition;
import org.springframework.stereotype.Service;

@Service
class VisibleItemsService implements VisibleItems {

    private final PullService pull;
    private final SyncRegistry registry;

    VisibleItemsService(PullService pull, SyncRegistry registry) {
        this.pull = pull;
        this.registry = registry;
    }

    @Override
    public List<ChangeEnvelope> visibleTo(UUID memberId, String entityType, Condition filter) {
        var type = registry.find(entityType)
                .orElseThrow(() -> HiwiskiException.invalid("sync.unknown_entity_type", "entityType", entityType));
        return pull.visibleTo(memberId, type, filter, LIMIT);
    }
}
