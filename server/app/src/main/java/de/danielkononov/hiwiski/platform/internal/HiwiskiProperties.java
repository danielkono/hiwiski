package de.danielkononov.hiwiski.platform.internal;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * The configuration of the instance.
 *
 * <p><strong>Every path is set; none has a silent default</strong>. In
 * an earlier version the blob store wrote into its working directory because the path was not set
 * anywhere -- in the image that is {@code /}, the process runs as uid 1000, and the result
 * was a server error for the user while the mounted volume next to it stayed empty.
 *
 * <p>{@code @Validated} with {@code @NotBlank} makes sure the server <strong>does not
 * start at all</strong> when a mandatory variable is missing. A server that comes up with
 * half a configuration fails later at a place that has nothing to do with the cause.
 */
@Validated
@ConfigurationProperties(prefix = "hiwiski")
record HiwiskiProperties(
        // Where the media store's images are written. No default.
        @NotBlank String mediaPath,

        // Where the backup archives are written. No default.
        @NotBlank String backupPath,

        // Oldest client version this server still serves. The handshake names it; a
        // client that is too old says so with a way to update, instead of failing at
        // some random place.
        @NotBlank String minClientVersion,

        // The operator's legal notice and privacy policy, for an instance open to the
        // public. Empty for a family's own server, which needs neither;
        // set, they must be absolute web addresses -- a typo stops the start instead of
        // showing a dead link in every app.
        @Pattern(regexp = WEB_ADDRESS) String legalNoticeUrl,
        @Pattern(regexp = WEB_ADDRESS) String privacyUrl) {

    /** Empty, or an absolute http(s) address. */
    static final String WEB_ADDRESS = "(https?://\\S+)?";
}
