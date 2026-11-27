package de.danielkononov.hiwiski.wiki.internal;

import de.danielkononov.hiwiski.sync.SyncProperty;
import java.util.List;
import org.springframework.stereotype.Component;

/**
 * A pinboard: a page with a title and a text like any other, and below them a canvas of
 * elements and connections.
 *
 * <p>The kind adds no properties. Its elements and connections are items of their own
 * ({@link PinboardSyncTypes}): as a property, the whole map would be one field, and two
 * people moving different elements would collide over all of it.
 */
@Component
class PinboardKind implements WikiKind {

    static final String CODE = "PINBOARD";

    @Override
    public String code() {
        return CODE;
    }

    @Override
    public List<SyncProperty> properties() {
        return List.of();
    }
}
