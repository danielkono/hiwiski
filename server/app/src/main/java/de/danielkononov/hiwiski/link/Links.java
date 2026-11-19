package de.danielkononov.hiwiski.link;

import java.util.List;
import java.util.UUID;

/** What other modules may know about references and trigger. */
public interface Links {

    /**
     * Re-reads the text and updates this item's references.
     *
     * <p>To be called when the text has changed. References are <strong>parsed from the
     * text, not maintained by hand</strong> — two truths would be one too many.
     */
    void reparse(String itemType, UUID itemId);

    /** Where this item points to. */
    List<Ref> outgoing(String itemType, UUID itemId, UUID reader);

    /** Who points to this item. */
    List<Ref> incoming(String itemType, UUID itemId, UUID reader);

    /**
     * @param title the target's current title — not the text that applied when it was
     *     written
     */
    record Ref(String itemType, UUID itemId, String title, String entityKey) {}
}
