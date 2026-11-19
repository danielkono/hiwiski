package de.danielkononov.hiwiski.admin.internal;

/** Why a backup was made. All of them count among the kept. */
enum BackupReason {
    SCHEDULED,
    ON_DEMAND,
    /** When the server starts with another version than it last ran. */
    BEFORE_UPDATE,
    /** Of the state a restore is about to replace, so that a restore by mistake can be undone. */
    BEFORE_RESTORE
}
