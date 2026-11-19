package de.danielkononov.hiwiski.platform;

/**
 * The five types that get a readable key.
 *
 * <p>There are no more, and that is intentional: a key should be easy to say and to copy
 * down ("have a look at TD-14"), and that only pays off where things actually get
 * cited.
 */
public enum KeyedEntityType {
    TODO(SettingKey.KEY_PREFIX_TODO, "TD"),
    EVENT(SettingKey.KEY_PREFIX_EVENT, "EVT"),
    WIKI_PAGE(SettingKey.KEY_PREFIX_WIKI_PAGE, "WIKI"),
    RECIPE(SettingKey.KEY_PREFIX_RECIPE, "REC"),
    TODO_LIST(SettingKey.KEY_PREFIX_TODO_LIST, "LST");

    private final String settingKey;
    private final String defaultPrefix;

    KeyedEntityType(String settingKey, String defaultPrefix) {
        this.settingKey = settingKey;
        this.defaultPrefix = defaultPrefix;
    }

    public String settingKey() {
        return settingKey;
    }

    public String defaultPrefix() {
        return defaultPrefix;
    }
}
