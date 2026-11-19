package de.danielkononov.hiwiski.platform;

/**
 * The known keys of the instance settings (platform).
 *
 * <p>They are constants here and not an enum: {@code instance_setting} is deliberately a
 * free key-value table, so that a new setting can be added without a migration. An enum
 * would nail that shut again.
 */
public final class SettingKey {

    /** The family's name. Appears in the handshake and on the login screen. */
    public static final String FAMILY_NAME = "family.name";

    /**
     * The family's identity -- made at setup and never changed, not by a restore
     * either. By it a running server tells its own archives from another family's,
     * which it refuses: that one belongs on a new server, through the setup wizard.
     */
    public static final String FAMILY_ID = "family.id";

    /** The family's home time zone. Input happens in the calendar's zone. */
    public static final String FAMILY_TIMEZONE = "family.timezone";

    /** Prefixes of the readable keys. Changing them only affects newly issued keys. */
    public static final String KEY_PREFIX_TODO = "key.prefix.TODO";
    public static final String KEY_PREFIX_EVENT = "key.prefix.EVENT";
    public static final String KEY_PREFIX_WIKI_PAGE = "key.prefix.WIKI_PAGE";
    public static final String KEY_PREFIX_RECIPE = "key.prefix.RECIPE";
    public static final String KEY_PREFIX_TODO_LIST = "key.prefix.TODO_LIST";

    /** Trash retention in days. Default 30. */
    public static final String RETENTION_TRASH_DAYS = "retention.trash.days";

    /**
     * Change log retention in days. Default 90, minimum 14.
     *
     * <p>Also limits how far back the history reaches.
     */
    public static final String RETENTION_LOG_DAYS = "retention.log.days";

    /**
     * The group every new member joins -- "Everyone" from the setup. By ID: a group
     * that happened to be first lost that role to whatever group came first next.
     */
    public static final String DEFAULT_GROUP = "group.default";

    /** Set to {@code true} once the setup wizard has been completed. */
    public static final String SETUP_COMPLETED = "setup.completed";

    /**
     * Identifier of this instance.
     *
     * <p>Regenerated on restore. Devices recognize by it that their sequence numbers no
     * longer apply, and sync from scratch. Without this identifier, devices would
     * silently keep working on a state that no longer exists -- the worst data loss
     * imaginable in this app.
     */
    public static final String INSTANCE_ID = "instance.id";

    /**
     * The scheduled backup: {@code DAILY} or {@code WEEKLY}, the weekday (ISO, 1 is
     * Monday), the time ({@code HH:mm} in the family's zone) and how many archives are
     * kept. There is no "off".
     */
    public static final String BACKUP_FREQUENCY = "backup.frequency";

    public static final String BACKUP_WEEKDAY = "backup.weekday";
    public static final String BACKUP_TIME = "backup.time";
    public static final String BACKUP_KEEP = "backup.keep";

    /**
     * The backup key: the age recipient every archive is encrypted to, and the private
     * key wrapped with the backup password -- never the password, never the bare key.
     * A restore keeps the current ones.
     */
    public static final String BACKUP_KEY_RECIPIENT = "backup.key.recipient";

    public static final String BACKUP_KEY_SLOT = "backup.key.slot";

    /** The last backup failed, and why -- until the next one succeeds. */
    public static final String BACKUP_FAILURE = "backup.failure";

    /**
     * The version the server last ran. Started with another one, it backs up before it
     * migrates.
     */
    public static final String SERVER_LAST_VERSION = "server.lastVersion";

    private SettingKey() {}
}
