package de.danielkononov.hiwiski.platform.internal;

import de.danielkononov.hiwiski.api.PlatformApi;
import de.danielkononov.hiwiski.api.model.Handshake;
import de.danielkononov.hiwiski.platform.CurrentRequest;
import de.danielkononov.hiwiski.platform.InstanceSettings;
import de.danielkononov.hiwiski.platform.RestoreInProgress;
import de.danielkononov.hiwiski.platform.SettingKey;
import de.danielkononov.hiwiski.platform.SetupCodeRequirement;
import java.net.URI;
import java.util.Optional;
import java.util.UUID;
import org.springframework.boot.info.BuildProperties;
import org.springframework.http.ResponseEntity;
import org.jspecify.annotations.Nullable;
import org.springframework.web.bind.annotation.RestController;

/**
 * The handshake: what kind of server is this, and does my app fit it?
 *
 * <p>Reachable without login -- the client calls it before it even has a token.
 */
@RestController
class HandshakeController implements PlatformApi {

    /** The major version of the contract. A real break is called {@code v2}. */
    private static final String API_VERSION = "v1";

    private final InstanceSettings settings;
    private final HiwiskiProperties properties;
    private final @Nullable BuildProperties build;
    private final RestoreInProgress restore;
    private final SetupCodeRequirement setupCode;

    HandshakeController(
            InstanceSettings settings,
            HiwiskiProperties properties,
            @Nullable BuildProperties build,
            RestoreInProgress restore,
            SetupCodeRequirement setupCode) {
        this.settings = settings;
        this.properties = properties;
        this.build = build;
        this.restore = restore;
        this.setupCode = setupCode;
    }

    @Override
    public ResponseEntity<Handshake> getHandshake() {
        boolean setupCompleted = settings.getBoolean(SettingKey.SETUP_COMPLETED, false);

        Handshake handshake =
                new Handshake(
                        API_VERSION,
                        build != null ? build.getVersion() : "dev",
                        properties.minClientVersion(),
                        setupCompleted,
                        isCleartext());
        // The wizard shows the code's field only where the server checks it: a field
        // that asks for something the family has no use for is the hurdle the setting
        // takes away.
        handshake.setSetupCodeRequired(setupCode.required());

        // As long as the instance is not set up, there is no family name. An empty
        // placeholder would be a claim.
        settings.find(SettingKey.FAMILY_NAME).ifPresent(handshake::setFamilyName);
        settings.find(SettingKey.INSTANCE_ID)
                .map(UUID::fromString)
                .ifPresent(handshake::setInstanceId);
        // Only an instance open to the public names them.
        nonBlank(properties.legalNoticeUrl()).map(URI::create).ifPresent(handshake::setLegalNoticeUrl);
        nonBlank(properties.privacyUrl()).map(URI::create).ifPresent(handshake::setPrivacyUrl);
        // Every app shows that it waits -- also one started again meanwhile.
        if (restore.since().isPresent()) {
            handshake.setRestoring(true);
        }

        return ResponseEntity.ok(handshake);
    }

    private static Optional<String> nonBlank(@Nullable String value) {
        return Optional.ofNullable(value).filter(text -> !text.isBlank());
    }

    /**
     * Is the connection running without TLS?
     *
     * <p>Behind Caddy the scheme comes from {@code X-Forwarded-Proto}, which Tomcat
     * applies only from a trusted proxy; without one the request's own scheme counts.
     * Read raw, the header let anyone claim TLS. The app says in plain words what
     * currently applies, instead of showing a padlock that is not one.
     */
    private boolean isCleartext() {
        return !"https".equalsIgnoreCase(CurrentRequest.get().getScheme());
    }
}
