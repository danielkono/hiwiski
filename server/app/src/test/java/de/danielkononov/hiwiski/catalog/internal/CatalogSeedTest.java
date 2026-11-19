package de.danielkononov.hiwiski.catalog.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** The shipped seeds read cleanly; a broken line says where. */
class CatalogSeedTest {

    @ParameterizedTest
    @ValueSource(strings = {"de", "en"})
    void everyShippedSeedReadsAgainstTheBuiltInCategories(String language) {
        assertThat(CatalogSeed.read(language)).isNotEmpty();
    }

    @Test
    void aLineWithoutATabNamesItsLine() {
        assertThatThrownBy(() -> CatalogSeed.parse("seed", "Milch\tdairy_eggs\nBrot\n"))
                .hasMessageContaining("seed:2");
    }

    @Test
    void anUnknownKeyIsRefused() {
        assertThatThrownBy(() -> CatalogSeed.parse("seed", "Milch\tdiary_eggs\n"))
                .hasMessageContaining("diary_eggs");
    }

    @Test
    void windowsLineEndsAndStraySpacesAreTrimmed() {
        var row = CatalogSeed.parse("seed", "Milch \tdairy_eggs\tl\r\n").getFirst();
        assertThat(row.name()).isEqualTo("Milch");
        assertThat(row.unit()).isEqualTo("l");
    }
}
