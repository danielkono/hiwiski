package de.danielkononov.hiwiski.admin.internal;

import java.nio.file.Path;

/**
 * An archive in the backup directory, as its header describes it -- without the
 * password.
 *
 * <p>"One archive, one button. Database dump plus images plus a manifest with schema and
 * server version, as one encrypted file."
 */
record BackupArchive(String id, Path file, ArchiveHeader header, long bytes) {}
