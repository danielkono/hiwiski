package de.danielkononov.hiwiski.platform;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Read and write access to the instance settings.
 *
 * <p>The keys are in {@link SettingKey}.
 */
public interface InstanceSettings {

    Optional<String> find(String key);

    /** Returns the value, or {@code fallback} if nothing is set. */
    String get(String key, String fallback);

    int getInt(String key, int fallback);

    boolean getBoolean(String key, boolean fallback);

    Map<String, String> all();

    void put(String key, String value, UUID actor);

    void putAll(Map<String, String> values, UUID actor);

    /** Removes the setting; reading it afterwards gives the fallback. */
    void remove(String key);
}
