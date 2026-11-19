package de.danielkononov.hiwiski.platform.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.core.io.FileSystemResource;

/** A file of the web client is told apart by what is in it. */
class WebClientEtagsTest {

    /** The date every file in a release image carries. */
    private static final FileTime IMAGE_DATE = FileTime.from(Instant.ofEpochSecond(1));

    private static Path write(Path file, String content) throws IOException {
        Files.writeString(file, content);
        Files.setLastModifiedTime(file, IMAGE_DATE);
        return file;
    }

    @Test
    void anotherReleaseOfAFileGetsAnotherTagThoughItsDateIsTheSame(@TempDir Path dir) throws IOException {
        // Two releases of the same file: the same length, the same date, other content.
        var before = new WebClientEtags().of(new FileSystemResource(write(dir.resolve("main.dart.js"), "release 1")));
        var after = new WebClientEtags().of(new FileSystemResource(write(dir.resolve("main.dart.js"), "release 2")));

        assertThat(after).isNotEqualTo(before);
        assertThat(before).startsWith("\"").endsWith("\"");
    }

    @Test
    void theSameFileKeepsItsTag(@TempDir Path dir) throws IOException {
        var file = new FileSystemResource(write(dir.resolve("main.dart.js"), "release 1"));
        var etags = new WebClientEtags();

        assertThat(etags.of(file)).isEqualTo(etags.of(file));
        // Another server process -- a restart, a second instance -- names it the same.
        assertThat(new WebClientEtags().of(file)).isEqualTo(etags.of(file));
    }

    @Test
    void aFileReplacedUnderARunningServerIsHashedAgain(@TempDir Path dir) throws IOException {
        var path = dir.resolve("main.dart.js");
        var etags = new WebClientEtags();
        var before = etags.of(new FileSystemResource(write(path, "a build")));

        Files.writeString(path, "the next build");

        assertThat(etags.of(new FileSystemResource(path))).isNotEqualTo(before);
    }
}
