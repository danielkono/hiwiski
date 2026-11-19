package de.danielkononov.hiwiski.identity;

/**
 * The setup wizard has run -- in the same transaction, before it commits.
 *
 * <p>For what other modules prepare once per instance: the catalog seeds its products in
 * the wizard's language. An event and not a call: {@code identity} does
 * not know {@code catalog}.
 *
 * @param language the language of the wizard's UI, e.g. {@code de}; {@code null} if an
 *     older app did not send it
 */
public record SetupCompleted(String language) {}
