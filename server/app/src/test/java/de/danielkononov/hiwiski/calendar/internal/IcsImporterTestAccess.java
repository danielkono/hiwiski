package de.danielkononov.hiwiski.calendar.internal;

import java.util.List;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

/**
 * The way into the package-private reader.
 *
 * <p>It lets us test what the acceptance case "an export in a third-party calendar app"
 * actually means: our own file must be readable by a *third-party* library. Writing is
 * done by hand, reading with ical4j — "other people's files are the problem, not our own".
 * Testing the writer only against our own writer tests
 * nothing.
 */
@TestConfiguration(proxyBeanMethods = false)
public class IcsImporterTestAccess {

    @Bean
    Reader icsReaderForTests(IcsImporter importer) {
        return new Reader(importer);
    }

    /** The narrow view the test needs. */
    public record Reader(IcsImporter importer) {

        /** How many VEVENTs a third-party library reads from the file. */
        public int count(String ics) {
            return importer.parse(ics).size();
        }

        /** The titles, in file order. */
        public List<String> titles(String ics) {
            return importer.parse(ics).stream().map(IcsImporter.Entry::title).toList();
        }

        /** The recurrence rules as the third-party library reads them. */
        public List<String> rrules(String ics) {
            return importer.parse(ics).stream()
                    .map(IcsImporter.Entry::rrule)
                    .filter(java.util.Objects::nonNull)
                    .toList();
        }
    }
}
