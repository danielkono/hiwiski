package de.danielkononov.hiwiski.wiki.internal;

import de.danielkononov.hiwiski.link.Links;
import de.danielkononov.hiwiski.platform.ChangeSequence;
import de.danielkononov.hiwiski.platform.CoveredWrites;
import de.danielkononov.hiwiski.sync.EntityWritten;
import java.util.UUID;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

/**
 * An element of a mind map changed: its page's references are parsed anew.
 *
 * <p>The page itself did not change, so nothing else would -- a link placed on the
 * canvas would never show at its target. The search index follows through
 * {@link WikiSearchable#affectedBy}.
 *
 * <p>Once per page for writes that come together: each parse reads the whole map, and
 * a page deleted or brought back with a thousand elements parsed it a thousand times
 * ({@link CoveredWrites}).
 *
 * <p>A bean of its own: {@link WikiLinkSource} reads the map's texts and is itself what
 * {@link Links} parses with, so the texts cannot depend on {@link Links} as well.
 */
@Component
class MindmapLinks {

    private final MindmapTexts texts;
    private final Links links;
    private final CoveredWrites<UUID> parsed;

    MindmapLinks(MindmapTexts texts, Links links, ChangeSequence sequence) {
        this.texts = texts;
        this.links = links;
        this.parsed = new CoveredWrites<>(sequence);
    }

    @ApplicationModuleListener
    void onEntityWritten(EntityWritten event) {
        texts.pageOf(event.entityType(), event.entityId())
                .ifPresent(page -> parsed.run(
                        page, event.version(), () -> links.reparse(WikiSyncTypes.PAGE_TYPE, page)));
    }
}
