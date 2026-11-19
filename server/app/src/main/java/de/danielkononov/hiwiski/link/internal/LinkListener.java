package de.danielkononov.hiwiski.link.internal;

import de.danielkononov.hiwiski.sync.EntityWritten;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * After every change: re-parse references.
 *
 * <p>References are <strong>parsed from the text, not maintained by hand</strong> — two
 * truths would be one too many. For that to hold, parsing has to
 * hang off every change and not off a button.
 *
 * <p>{@code @ApplicationModuleListener} means: after the commit, in a transaction of its
 * own, and the call is recorded in {@code event_publication}. A restart in the middle of
 * the follow-up therefore does not lose it — and a parse error does not bring down the
 * mutation that was just saved.
 */
@Component
class LinkListener {

    private final LinkService links;

    LinkListener(LinkService links) {
        this.links = links;
    }

    @ApplicationModuleListener
    void onEntityWritten(EntityWritten event) {
        links.reparse(event.entityType(), event.entityId());
    }
}
