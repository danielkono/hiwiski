package de.danielkononov.hiwiski.platform;

/**
 * Issues the readable keys: {@code TD-14}, {@code EVT-01}, {@code WIKI-3},
 * {@code REC-12}, {@code LST-3}.
 *
 * <p>The key is a <em>label</em>, not a second identity: the UUID is the identity, and
 * every foreign key points to it. The key is a nullable display column on five tables
 * and never changes once issued.
 *
 * <p>It is issued <strong>exactly once</strong>, on the first sync to the server. Items
 * created offline do not have one yet; the UI shows a dash there. Imported events get
 * none at all -- they belong to their source, and a school-holiday calendar would use up
 * five hundred numbers for something nobody cites.
 */
public interface EntityKeys {

    /**
     * Draws the next key for this type, with the currently configured prefix. Runs in
     * the caller's transaction: if the creation is rolled back, the number is free
     * again.
     */
    String next(KeyedEntityType type);
}
