package de.danielkononov.hiwiski.link;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import de.danielkononov.hiwiski.link.internal.LinkParserTestAccess;
import java.time.Duration;
import org.junit.jupiter.api.Test;

/**
 * Text no one writes on purpose, but a member can: the parser runs after every save, and
 * a text it cannot read means the item's links and backlinks are never written again.
 *
 *
 */
class LinkParserHostileTextTest {

    private static final String LINK = "[Router](hiwiski://wiki_page/01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071)";

    @Test
    void anUnclosedBracketBeforeALongLineDoesNotOverflowTheStack() {
        String text = "[" + "a".repeat(10_000) + "\n" + LINK;

        assertThat(LinkParserTestAccess.parse(text))
                .containsExactly("uri:WIKI_PAGE/01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071");
    }

    @Test
    void anUnclosedBracketBeforeAMegabyteDoesNotOverflowTheStack() {
        String text = "[" + "a\\]".repeat(400_000);

        assertThat(LinkParserTestAccess.parse(text)).isEmpty();
    }

    @Test
    void aLineOfBracketsIsReadInLinearTime() {
        String text = "[".repeat(200_000) + "\n" + LINK + " #TD-1";

        var found = assertTimeoutPreemptively(Duration.ofMillis(500), () -> LinkParserTestAccess.parse(text));

        assertThat(found).containsExactly("uri:WIKI_PAGE/01932b3c-4d5e-7f80-8a1b-2c3d4e5f6071", "key:TD-1");
    }
}
