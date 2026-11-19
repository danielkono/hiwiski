package de.danielkononov.hiwiski.link;

import static org.assertj.core.api.Assertions.assertThat;

import de.danielkononov.hiwiski.link.internal.LinkParserTestAccess;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.TestFactory;
import tools.jackson.databind.ObjectMapper;

/**
 * Link parsing against {@code golden/links.json}.
 *
 * <p>The client tests the same file. The server parses the text to write the {@code link}
 * table; the device parses it to draw the chips and fill the info bar offline. "Links are
 * parsed from the text, not maintained by hand" does not mean there
 * may be two readings of the same text.
 *
 * <p>Not an integration test: parsing needs no database, and a test that boots a container
 * for it eventually gets skipped.
 */
class LinkParserGoldenTest {

    private static final Path GOLDEN = Path.of("../../golden/links.json");

    @SuppressWarnings("unchecked")
    @TestFactory
    Stream<DynamicTest> everyCaseFromTheGoldenFile() throws Exception {
        Map<String, Object> document = new ObjectMapper().readValue(Files.readString(GOLDEN), Map.class);
        List<Map<String, Object>> cases = (List<Map<String, Object>>) document.get("cases");

        assertThat(cases).isNotEmpty();

        return cases.stream().map(testCase -> DynamicTest.dynamicTest(
                String.valueOf(testCase.get("name")),
                () -> assertThat(LinkParserTestAccess.parse((String) testCase.get("text")))
                        .describedAs("%s — %s", testCase.get("name"), testCase.get("why"))
                        .isEqualTo(testCase.get("expected"))));
    }
}
